//
//  RequestHelper.swift
//  PodDemo3
//
//  Created by KOYO on 2022/9/30.
//

import Foundation
import Starscream
import SwiftyJSON
import WebRTC

protocol RequestHelperDelegate {
    
    func onNewConsumerUpdateUI(helper:RequestHelper,consumer:Consumer)
    func getLocalRanderView(helper:RequestHelper)->RTCEAGLVideoView
}

class RequestHelper : NSObject{
    
    var delegate:RequestHelperDelegate?
    private var socket:WebSocket?
    ///是否已经加入到房间
    public var joinedRoom = false
    private var device:MediasoupDevice?
    private var sendTransport:SendTransport?
    private var sendListener:MySendTransportListener!
    private var recvTransport:RecvTransport?
    private var recvListener:MyRecvTransportListener!
    private var producerHandler:ProducerHandler!
    private var consumerHandler:ConsumerHandler!
    
    private var peerConnectionFactory:RTCPeerConnectionFactory?
    private var mediaStream:RTCMediaStream?
    private var totalProducers:[String:Producer] = [:]
    var totalConsumers:[String:Consumer] = [:]
    private var videoCapture:RTCCameraVideoCapturer?
    private var isStaredVideo = false
    
    var consumersInfoAudios:[[String:Any]] = []
    var consumersInfoVideos:[[String:Any]] = []
    private var peersIDs:[String] = []
    private var socketIp = ""
    private var roomId = ""
    
    
    public static func create(_ socket:WebSocket,ip:String,roomId:String)->RequestHelper {
        let helper = RequestHelper()
        helper.socketIp = ip
        helper.initSome()
        helper.roomId = roomId
        helper.socket = socket
        helper.socket?.delegate = helper
        return helper
    }
    
    private func initSome(){
        if peerConnectionFactory == nil{
            peerConnectionFactory = RTCPeerConnectionFactory()
        }
        if mediaStream == nil{
            mediaStream = peerConnectionFactory?.mediaStream(withStreamId: ARDEmu.kARDMediaStreamId)
        }
    }
    
    public func connect(){
        socket?.connect()
    }
    
    
    private func onSocketConnected(){
        let capabilities = onGetCapabilities()
        guard let device = MediasoupDevice() else{return}
        device.load(capabilities)
        if !(device.canProduce("audio")) {
            print(" 不支持音频===2===")
        }
        if !(device.canProduce("video")) {
            print(" 不支持视频===2===")
        }
        self.device = device
        
        
        onCreateSendTransport()
        onCreateRecvTransport()
        onJoinRoom(device: device)
        startVideoAndAudio()
    }
    
    ///通用发送数据接口
    private func sendData(id:Int,method:String,data:[String:Any]){
        let body:JSON = JSON(data)
        let sendData:JSON = ["request":NSNumber.init(value: true),
                             "id":id,
                             "method":method,
                             "data":body]
        print("\r\n即将\(String(describing: Thread.current.name))*********写入数据:\(sendData.description)\r\n")
        self.socket?.write(string: sendData.description, completion: nil)
    }
    
    ///获取Send，Recv 管道创建的参数
    private func questSendOrRecvTransportParam(isSend:Bool){
        let trueVal = NSNumber.init(value: true)
        let falseVal = NSNumber.init(value: false)
        
        let data:[String:Any] = ["forceTcp":falseVal,
                                 "producing":isSend ? trueVal : falseVal,
                                 "consuming":isSend ? falseVal : trueVal]
        let id = isSend ? ActionEventID.kCreateSendID : ActionEventID.kCreateRecvID
        sendData(id:id,method: ActionEvent.createWebRtcTransport, data: data)
    }
}

extension RequestHelper{
    
    ///请求连接串
    public func onGetCapabilities()->String{
        guard let socket = self.socket else{return ""}
        let message = Message(socket: socket,messageId: ActionEventID.kConnectID)
        let data:[String:Any] =  ["action":"getRoomRtpCapabilities","roomId":roomId]
        let result = message.send(method: ActionEvent.getRouterRtpCapabilities, data: data)
        let json:JSON = JSON(result)
        print("连接串获取成功。。。")
        return json.description
        
    }
    
    ///建立发送通道
    public func onCreateSendTransport(){
        guard let socket = self.socket else{return}
        let trueVal = NSNumber.init(value: true)
        let falseVal = NSNumber.init(value: false)
        
        let params:[String:Any] = ["forceTcp":falseVal,
                                   "producing":trueVal,
                                   "consuming":falseVal]
        
        let message = Message(socket: socket,messageId: ActionEventID.kCreateSendID)
        let transportDic = message.send(method: ActionEvent.createWebRtcTransport, data: params)
        
        let id = transportDic.strValue("id")
        let iceParameters = JSON(transportDic.dictionary("iceParameters")).description
        var iceCandidatesArray = transportDic.array("iceCandidates")
        if var first = iceCandidatesArray.first{
            
            first["ip"] = socketIp
            iceCandidatesArray[0] = first
        }
        let iceCandidates = JSON(iceCandidatesArray).description
        let dtlsParameters = JSON(transportDic.dictionary("dtlsParameters")).description
        
        self.sendListener = MySendTransportListener()
        self.sendListener.helper = self
        
        self.sendTransport = device?.createSendTransport(self.sendListener, id:id, iceParameters: iceParameters, iceCandidates: iceCandidates, dtlsParameters: dtlsParameters)
    }
    
    //建立接收通道
    public func onCreateRecvTransport(){
        guard let socket = self.socket else{return}
        let trueVal = NSNumber.init(value: true)
        let falseVal = NSNumber.init(value: false)
        
        let data:[String:Any] = ["forceTcp":falseVal,
                                 "producing":falseVal,
                                 "consuming":trueVal]
        let message = Message(socket: socket,messageId: ActionEventID.kCreateSendID)
        let dataDic = message.send(method: ActionEvent.createWebRtcTransport, data: data)
        
        let id = dataDic.strValue("id")
        let iceParameters = JSON(dataDic.dictionary("iceParameters")).description
        var iceCandidatesArray = dataDic.array("iceCandidates")
        if var first = iceCandidatesArray.first{
            first["ip"] = socketIp
            iceCandidatesArray[0] = first
        }
        let iceCandidates = JSON(iceCandidatesArray).description
        let dtlsParameters = JSON(dataDic.dictionary("dtlsParameters")).description
        
        self.recvListener = MyRecvTransportListener()
        self.recvListener.helper = self
        self.recvTransport = device?.createRecvTransport(self.recvListener, id: id, iceParameters: iceParameters, iceCandidates: iceCandidates, dtlsParameters: dtlsParameters)
        
    }
    
    ///加入房间
    public func onJoinRoom(device:MediasoupDevice){
        
        if !device.isLoaded() {
            print("设备已加载，直接返回")
            return
        }
        if joinedRoom{
            print("已加入到房间，直接返回")
            return
        }
        
        guard let socket = self.socket else{return}
        let deviceRtpCapabilities = device.getRtpCapabilities() ?? ""
        let data:[String:Any] = [
            "device":SocketUtil.deviceInfo(),
            "displayName":"张三",
            "rtpCapabilities": JSON.init(parseJSON: deviceRtpCapabilities)
        ]
        
        let message = Message(socket: socket, messageId: ActionEventID.kJoinID)
        let _ = message.send(method: ActionEvent.join, data: data)
        //房间里已经正在通话的人
        //        let peers = result.array("peers")
        //        for peer in peers{
        //            self.peersIDs.append(peer.strValue("id"))
        //        }
        self.joinedRoom = true
    }
    
    ///创建生产者
    func onProduceCallBack(transportId:String,kind:String,rtpParameters:String)->[String:Any]{
        guard let socket = self.socket else{return [:]}
        let rtpDic = rtpParameters.toDic()
        let params:[String:Any] = ["transportId":transportId,"kind":kind,"rtpParameters":rtpDic]
        let message = Message(socket: socket, messageId: ActionEventID.kProduce)
        let result = message.send(method: ActionEvent.produce, data: params)
        return result
    }
    
    ///接通新用户
    public func onConnectCallBack(transportId:String,dtlsParameters:String){
        guard let socket = self.socket else{return}
        let dtl = dtlsParameters.toDic()
        let params:[String:Any] = ["transportId": transportId,"dtlsParameters":dtl]
        
        let message = Message(socket: socket, messageId:SocketUtil.getSocketKey())
        let _ = message.send(method: ActionEvent.connectWebRtcTransport, data: params)
        
    }
    
    ///测试管道
    public func sendResponse(requestId:Int){
        let sendData:JSON = ["response":NSNumber.init(value: true),
                             "id":requestId,
                             "ok" :NSNumber.init(value: true),
                             "data":""]
        print("发送空数据:\(sendData.description)")
        socket?.write(string: sendData.description, completion: nil)
    }
}

extension RequestHelper{
    
    func consumerClosed(consumerId:String){
        for (i,item) in consumersInfoVideos.enumerated() {
            let idV = item.strValue("id")
            if idV == consumerId {
                consumersInfoVideos.remove(at: i)
            }
        }
        for (i,item) in consumersInfoAudios.enumerated() {
            let idV = item.strValue("id")
            if idV == consumerId {
                consumersInfoAudios.remove(at: i)
            }
        }
        print("用户已退出。。。。")
    }
    
}



extension RequestHelper{
    func createConsumerAndResume(){
        self.consumerHandler = ConsumerHandler()
        
        print("已存在视频数量:\(self.consumersInfoVideos.count)")
        print("已存在音频数量:\(self.consumersInfoVideos.count)")
        
        for consumerAudio in self.consumersInfoAudios{
            //音频
            let requestIdA = consumerAudio.intValue("requestId")
            let kindA = consumerAudio.strValue("kind")
            let idA = consumerAudio.strValue("id")
            let producerIdA = consumerAudio.strValue("producerId")
            let rtpParametersA = consumerAudio.dictionary("rtpParameters")
            let paramsJsonA = JSON(rtpParametersA).description
            print("\r\n准备循环创建consume 音频")
            guard let consumer = self.recvTransport?.consume(self.consumerHandler, id: idA, producerId: producerIdA, kind: kindA, rtpParameters:paramsJsonA) else{
                print("订阅新用户音频失败")
                return
            }
            self.totalConsumers[consumer.getId()] = consumer
            self.sendResponse(requestId: requestIdA)
            print("\r\n完成循环创建consume 音频")

        }
        
        for consumerVideo in self.consumersInfoVideos{
            //视频
            let requestIdV = consumerVideo.intValue("requestId")
            let kindV = consumerVideo.strValue("kind")
            let idV = consumerVideo.strValue("id")
            let producerIdV = consumerVideo.strValue("producerId")
            let rtpParametersV = consumerVideo.dictionary("rtpParameters")
            let rtp = JSON(rtpParametersV).description
            let appData = JSON(consumerVideo.dictionary("appData")).description
            let peerId = consumerVideo.strValue("peerId")
            
            print("\r\n准备循环创建(\(peerId))的consume --视频")
            guard let consumer = self.recvTransport?.consume(self.consumerHandler, id: idV, producerId: producerIdV, kind: kindV, rtpParameters:rtp,appData: appData)else{
                print("订阅新用户视频失败")
                return
            }
            self.totalConsumers[consumer.getId()] = consumer
            
            self.delegate?.onNewConsumerUpdateUI(helper: self, consumer: consumer)
            self.sendResponse(requestId: requestIdV)
            print("\r\n完成循环创建consume ---视频\r\n")
        }
    }
    
    
    
    
    ///开启音视频4
    private func startVideoAndAudio() {
        print("准备开启音视频 ：\(Thread.current)")
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: { (isGranted: Bool) in
                self.startAudio()
            })
        } else {
            self.startAudio()
        }
        
        print("准备开启视频startVideo()：\(Thread.current)")
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { (isGranted: Bool) in
                self.startVideo()
            })
        } else {
            self.startVideo()
        }
        
    }
    
    //构建视频
    func startVideo(){
        
        
        guard let cameraDevice = SocketUtil.getCameraDevice()else{return}
        
        guard let videoSource = peerConnectionFactory?.videoSource() else{return}
        videoSource.adaptOutputFormat(toWidth: 144, height: 192, fps: 30)
        videoCapture = RTCCameraVideoCapturer(delegate: videoSource)
        
        guard let format = RTCCameraVideoCapturer.supportedFormats(for: cameraDevice).last else{return}
        
        let fps:Int = Int(format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30)
        
        videoCapture?.startCapture(with: cameraDevice, format:format, fps: fps)
        
        guard let videoTrack = peerConnectionFactory?.videoTrack(with: videoSource, trackId: ARDEmu.kARDVideoTrackId) else{return}
        videoTrack.isEnabled = true
        guard let localVideoView = delegate?.getLocalRanderView(helper: self) else{return}
        self.mediaStream?.addVideoTrack(videoTrack)
        videoTrack.add(localVideoView)
        
        let codecOptions: JSON = [
            "videoGoogleStartBitrate": 1000
        ]
        print("\r\n准备创建视频produce()，thread:\(Thread.current)")
        self.producerHandler = ProducerHandler()
        guard let producer = self.sendTransport?.produce(producerHandler, track: videoTrack, encodings: nil, codecOptions: codecOptions.description) else{
            print("创建失败........error")
            return
        }
        print("\r\n视频---produce创建成功1111")
        self.totalProducers[producer.getId()] = producer
        
        createConsumerAndResume()
        
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoChat, options: .defaultToSpeaker)
    }
    
    ///构建音频
    func startAudio(){
        
        guard let audioTrack = peerConnectionFactory?.audioTrack(withTrackId: ARDEmu.kARDAudioTrackId) else{return}
        audioTrack.isEnabled = true
        mediaStream?.addAudioTrack(audioTrack)
        print("\r\n准备创建音频 produce")
        self.producerHandler = ProducerHandler()
        guard let kindProducer = self.sendTransport?.produce(self.producerHandler, track: audioTrack, encodings:nil, codecOptions:nil) else{
            print("sendTransport  创建失败。。。。。。")
            return
        }
        print("\r\n音频创建成功1111")
        self.totalProducers[kindProducer.getId()] = kindProducer
    }
}


extension RequestHelper:WebSocketDelegate{
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        //        print("RequestHelper收到消息。。\(event)")
        switch event {
        case .connected(let dictionary):
            //            print("链接成功:\(dictionary)")
            self.onSocketConnected()
        case .disconnected(let string, let uInt16):
            print("已断开:\(string)")
            
        case .text(let string):
            let dic = string.toDic()
            //            let method = dic.strValue("method")
            onDidReceiveMessage(message: dic)
            
        case .binary(let data):
            print("binary----optional:\(data)")
        case .pong(let optional):
            print("pong----optional:\(String(describing: optional))")
            
        case .ping(let optional):
            print("ping----optional:\(String(describing: optional))")
            
        case .error(let optional):
            print("error----optional:\(String(describing: optional))")
            
        case .viabilityChanged(let bool):
            print("viabilityChanged----bool:\(bool)")
        case .reconnectSuggested(let bool):
            print("reconnectSuggested----bool:\(bool)")
            
        case .cancelled:
            print("cancelled----")
        }
        
    }
    
    func onDidReceiveMessage(message:[String:Any]) {
        
        let requestId = message.intValue("id")
        let method = message.strValue("method")
        let data = message.dictionary("data")
        
        if method == "activeSpeaker" || method == "downlinkBwe"{
            return
        }
        if method == "newConsumer"{
            print("\r 收到数据： (\(message) \r\n")
        }
        //        if requestId != ActionEventID.kConnectID{
        print("\r 收到数据method： (\(method) \r\n")
        //        }
        
        NotificationCenter.default.post(name: NSNotification.Name("kOnRecveMessage"), object: message)
        if method == "newConsumer"{
            //这里一定要把requestId加入，因为里面后期都是取的这个字段进行订阅
            var consumerIndoDic:[String:Any] = data
            consumerIndoDic["requestId"] = requestId
            let kind = consumerIndoDic.strValue("kind")
            
            //音频
            if kind == "audio"{
                self.consumersInfoAudios.append(consumerIndoDic)
                //视频
            }else{
                self.consumersInfoVideos.append(consumerIndoDic)
            }
            if !peersIDs.isEmpty{
                let id = consumerIndoDic.strValue("id")
                let producerId = consumerIndoDic.strValue("producerId")
                let rtpParameters = JSON(consumerIndoDic.dictionary("rtpParameters")).description
                let appData = JSON(consumerIndoDic.dictionary("appData")).description
                print("\r\n准备创建新用户\npeersIDs:  \(peersIDs)，\nid:  \(id),  \nproducerId:  \(producerId)，kind:\(kind),\(Thread.current)")
                
                //订阅该用户对应的视频、音频数据
                guard let consumer = self.recvTransport?.consume(self.consumerHandler, id: id, producerId: producerId, kind: kind, rtpParameters: rtpParameters,appData:appData) else{
                    print("新用户加入。。。。。失败了。。。。。")
                    return
                }
                print("***newConsumer创建成功****\(kind)  id:\(String(describing: consumer.getId())), \(Thread.current)")
                self.totalConsumers[consumer.getId()] = consumer
                if kind == "video"{
                    self.delegate?.onNewConsumerUpdateUI(helper: self, consumer: consumer)
                    print("UI更新完成")
                }
                self.sendResponse(requestId:requestId)
            }
            
        }else if method == "newPeer"{
            let id = data.strValue("id")
            self.peersIDs.append(id)
            
        }else if method == "consumerClosed"{
            print("---method用户已退出-->\(method)")
            consumerClosed(consumerId: data.strValue("consumerId"))
        }
        
    }
}
