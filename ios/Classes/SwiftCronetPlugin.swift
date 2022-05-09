//
//  CronetPlugin.swift
//  cronet
//
//  Created by Jimmy on 2022/5/9.
//

import Flutter
import UIKit


public class SwiftGalleryPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cronet", binaryMessenger: registrar.messenger())
        let instance = SwiftGalleryPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

