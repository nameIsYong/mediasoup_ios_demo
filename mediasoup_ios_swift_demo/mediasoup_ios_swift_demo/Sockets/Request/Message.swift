//
//  Message.swift
//  PodDemo3
//
//  Created by KOYO on 2022/11/7.
//

import Foundation
//import SocketRocket
import Starscream
//import SwiftWebSocket
import SwiftyJSON

class Message: NSObject {
    
    private var socket:WebSocket!
    private let semaphare = DispatchSemaphore(value: 0)
    //消息ID，每条消息都有个ID，多线程情况下用来区分那条消息对应服务器返回的数据
    private var messageId = 0
    private var response:[String:Any] = [:]
    
    init(socket:WebSocket,messageId:Int) {
        super.init()
        self.socket = socket
        self.messageId = messageId
        registeNotify()
    }
    
    private func registeNotify() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(onRecveMessage(sender:)), name: NSNotification.Name(rawValue:"kOnRecveMessage"), object: nil)
    }
    
    @objc private func onRecveMessage(sender: Notification) {
        if let dic = sender.object as? [String:Any]{
            let requestId = dic.intValue("id")
            if requestId != self.messageId{
                print("\(requestId)非我的\(self.messageId)消息，继续等待..")
                return
            }
            self.response = dic.dictionary("data")
            semaphare.signal()
        }
        
    }
    
    ///删除所有已注册的通知
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    //发送消息
    func send(method:String,data:[String:Any])->[String:Any]{
        
        let body:JSON = JSON(data)
        let sendData:JSON = ["request":NSNumber.init(value: true),
                             "id":self.messageId,
                             "method":method,
                             "data":body]
        print("发送数据:\(sendData.description)")

        socket.write(string: sendData.description, completion: nil)
        semaphare.wait()
        return self.response
    }
}

