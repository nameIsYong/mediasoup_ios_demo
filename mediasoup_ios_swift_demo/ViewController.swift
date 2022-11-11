//
//  ViewController.swift
//  PodDemo3
//
//  Created by KOYO on 2022/4/23.
//

import UIKit
import Starscream
import SwiftyJSON
import WebRTC


class ViewController: UIViewController {
    
    private var collectionView:ChatCollectionView!
    private var command:RequestHelper!
    
    //自己
    @IBOutlet var localVideoView: RTCEAGLVideoView!
    //远端
    @IBOutlet weak var remoteVideoBGView: UIView!
    
    private var kSocketIp = "v3demo.mediasoup.org"//"192.168.5.93"//
    private let roomId = "9528"
    private let peerId = "thisIsMyID6"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
    }
  
    @IBAction func onConnect(_ sender: UIButton) {
        //69  93
        print("开始连接。。。")
        let url = URL(string: "wss://\(kSocketIp):4443?roomId=\(roomId)&peerId=\(peerId)")!
        var request = URLRequest(url: url)
        request.setValue("protoo", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        let pinner = FoundationSecurity(allowSelfSigned: true)
        let compression = WSCompression()
        let socket = WebSocket(request: request, certPinner:pinner, compressionHandler: compression)
        socket.callbackQueue = DispatchQueue.global()
        
        command = RequestHelper.create(socket, ip: kSocketIp, roomId: roomId)
        command.delegate = self
        command.connect()
        
    }
    

}



extension ViewController:RequestHelperDelegate{
    
    func onNewConsumerUpdateUI(helper: RequestHelper, consumer: Consumer) {
        print("\r\n准备更新UI  \(Thread.current)")
        
        if let videoTrack = consumer.getTrack() as? RTCVideoTrack{
            
            videoTrack.isEnabled = true
            DispatchQueue.main.async {
                for view in self.remoteVideoBGView.subviews{
                    print("删除子控件。。\(view)")
//                    view.removeFromSuperview()
                    return
                }
                print("\r\n更新UI \(Thread.current)")
                let videoView = RTCEAGLVideoView(frame: self.remoteVideoBGView.bounds)
                self.remoteVideoBGView.addSubview(videoView)
                videoTrack.add(videoView)
            }
            
        }else{
            print("刷新UI失败")
        }
    }
    
    func getLocalRanderView(helper: RequestHelper) -> RTCEAGLVideoView {
        return self.localVideoView
    }
}
