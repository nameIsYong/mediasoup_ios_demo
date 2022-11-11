//
//  MySendTransportListener.swift
//  PodDemo3
//
//  Created by 勇胡 on 2022/11/7.
//

import Foundation
//import SocketRocket

import SwiftyJSON
import WebRTC


//发送管道的监听
class MySendTransportListener:NSObject,SendTransportListener{
    
    public var helper:RequestHelper!
    //本地视频资源是否构建完成
    private var isVideoLaunchFinish = false
    private var isAudioLaunchFinish = false
    private var dtlsParameters = ""
    
    //管道创建成功回调
    func onConnect(_ transport: Transport!, dtlsParameters: String!) {
        print("\r\n ********SendTransportListener onConnect \(Thread.current)\r\n \(transport.getId()!)\r\n")
        self.dtlsParameters = dtlsParameters
    }
    
    func onConnectionStateChange(_ transport: Transport!, connectionState: String!) {
        print("SendTransportListener onConnectionStateChange:\(String(describing: connectionState))")
        if connectionState.contains("disconnected"){
            transport.close()
        }
    }
    
    func onProduce(_ transport: Transport!, kind: String!, rtpParameters: String!, appData: String!, callback: ((String?) -> Void)!) {
        print("\r\n ********MySendTransportListener(onProduce) \r\n \(transport.getId()!),\(kind!),\(Thread.current), rtpParameters:\(rtpParameters!)\r\n")
        let result = self.helper.onProduceCallBack(transportId: transport.getId(), kind: kind, rtpParameters: rtpParameters)
        callback?(result.strValue("id"))
        
        if kind == "video"{
            self.isVideoLaunchFinish = true
        }
        if kind == "audio"{
            self.isAudioLaunchFinish = true
        }
        
        let transportId = transport.getId() ?? ""

        if self.isAudioLaunchFinish && self.isVideoLaunchFinish {
            print("检查是否都完成了，调用onConnectCallBack")
            self.helper.onConnectCallBack(transportId:transportId, dtlsParameters:self.dtlsParameters)
        }
    }
}


//接收管道的监听
class MyRecvTransportListener : NSObject, RecvTransportListener{
    public var helper:RequestHelper!
    
    func onConnect(_ transport: Transport!, dtlsParameters: String!) {
        let id = transport.getId() ?? ""
       
//        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now()+2.5) {
            print("\r\n *********MyRecvTransportListener(onConnect) \r\n:\(id),\(Thread.current)\r\n")
            self.helper.onConnectCallBack(transportId: id, dtlsParameters: dtlsParameters)
//         }

    }
    
    func onConnectionStateChange(_ transport: Transport!, connectionState: String!) {
        print("MyRecvTransportListener  onConnectionStateChange:\(String(describing: connectionState))  (\(transport.getId())) ")
        if connectionState.contains("disconnected"){
            transport.close()
        }
    }
    

}

class ProducerHandler:NSObject,ProducerListener{
    
    func onTransportClose(_ producer: Producer!) {
        print("ProducerHandler--onTransportClose-")
    }
}

class ConsumerHandler:NSObject,ConsumerListener{
    
    func onTransportClose(_ consumer: Consumer!) {
        print("ConsumerHandler--onTransportClose-")
    }
}

