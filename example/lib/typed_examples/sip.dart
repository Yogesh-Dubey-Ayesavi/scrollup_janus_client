import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:janus_client/janus_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client_example/conf.dart';

class TypedSipExample extends StatefulWidget {
  @override
  _SipExampleState createState() => _SipExampleState();
}

class _SipExampleState extends State<TypedSipExample> {
  late JanusClient j;
  late WebSocketJanusTransport ws;
  late JanusSession session;
  late JanusSipPlugin sip;
  TextEditingController proxyController =
      TextEditingController(text: "sip:sip.theansr.com");
  TextEditingController usernameController =
      TextEditingController(text: "sip:test_janus@sip.theansr.com");
  TextEditingController secretController =
      TextEditingController(text: "+iBBfWDygkaF8P21tXkV");
  TextEditingController callUriController =
      TextEditingController(text: "sip:00918744849050@sip.theansr.com");
  RTCVideoRenderer _remoteVideoRenderer = RTCVideoRenderer();
  // MediaStream? localStream;
  MediaStream? remoteVideoStream;
  MediaStream? remoteAudioStream;
  dynamic incomingDialog;
  MediaStream? localStream;

  dynamic registerDialog;
  dynamic callDialog;

  Future<void> localMediaSetup() async {
    MediaStream? temp = await sip.initializeMediaDevices();
    localStream = temp;
  }

  makeCall() async {
    await localMediaSetup();
    await sip.call(callUriController.text);
    // nameController.text = "";
  }

  openRegisterDialog() async {
    registerDialog = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            insetPadding: EdgeInsets.zero,
            title: Text("Register As"),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.9,
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    TextFormField(
                      decoration: InputDecoration(
                          labelText: "Sip Server URI",
                          hintText: "sip:host:port"),
                      controller: proxyController,
                      validator: (val) {
                        if (val == '') {
                          return 'uri can\'t be empty! ';
                        }
                      },
                    ),
                    TextFormField(
                      decoration: InputDecoration(
                          labelText: "Sip username",
                          hintText: "sip:test@host:port"),
                      controller: usernameController,
                      validator: (val) {
                        if (val == '') {
                          return 'uri can\'t be empty! ';
                        }
                      },
                    ),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: "Sip password",
                      ),
                      obscureText: true,
                      controller: secretController,
                      validator: (val) {
                        if (val == '') {
                          return 'uri can\'t be empty! ';
                        }
                      },
                    ),
                    Padding(padding: EdgeInsets.all(9)),
                    ElevatedButton(
                      onPressed: () {
                        registerUser();
                      },
                      child: Text("Proceed"),
                    )
                  ],
                ),
              ),
            ),
          );
        });
  }

  makeCallDialog() async {
    callDialog = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text("Call Registered User or wait for user to call you"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: InputDecoration(labelText: "sip URI to call"),
                  controller: callUriController,
                ),
                ElevatedButton(
                  onPressed: () {
                    makeCall();
                  },
                  child: Text("Call"),
                )
              ],
            ),
          );
        });
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    await _remoteVideoRenderer.initialize();
  }

  initJanusClient() async {
    ws = WebSocketJanusTransport(url: servermap['janus_ws']);
    j = JanusClient(
        transport: ws,
        iceServers: [
          RTCIceServer(
              urls: "stun:stun.voip.eutelia.it:3478",
              username: "",
              credential: "")
        ],
        isUnifiedPlan: true);
    session = await j.createSession();
    sip = await session.attach<JanusSipPlugin>();
    await _remoteVideoRenderer.initialize();
    MediaStream? tempVideo = await createLocalMediaStream('remoteVideoStream');
    setState(() {
      remoteVideoStream = tempVideo;
    });
    sip.remoteTrack?.listen((event) async {
      if (event.track != null && event.flowing == true) {
        remoteVideoStream?.addTrack(event.track!);
        _remoteVideoRenderer.srcObject = remoteVideoStream;
        // this is done only for web since web api are muted by default for local tagged mediaStream
        if (kIsWeb) {
          _remoteVideoRenderer.muted = false;
        }
      }
    });
    sip.typedMessages?.listen((even) async {
      Object data = even.event.plugindata?.data;
      if (data is SipRegisteredEvent) {
        print(data.toJson());
        Navigator.of(context).pop();
        await makeCallDialog();
      }
      if (data is SipIncomingCallEvent) {
        var dialog =
            await showIncomingCallDialog(data.result?.callee, even.jsep);
        setState(() {
          incomingDialog = dialog;
        });
      }

      if (data is SipAcceptedEvent) {
        sip.handleRemoteJsep(even.jsep);
      }
      if (data is SipProgressEvent) {
        sip.handleRemoteJsep(even.jsep);
      }
    }, onError: (error) async {
      if (error is JanusError) {
        var dialog;
        dialog = await showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                actions: [
                  TextButton(
                      onPressed: () async {
                        await stopAllTracksAndDispose(localStream);
                        Navigator.of(context).pop(dialog);
                        // nameController.clear();
                      },
                      child: Text('Okay'))
                ],
                title: Text('Whoops!'),
                content: Text(error.error),
              );
            });
      }
    });
    await openRegisterDialog();
  }

  @override
  void initState() {
    super.initState();
    initJanusClient();
  }

  GlobalKey<FormState> formKey = GlobalKey();

  Future<void> registerUser() async {
    if (formKey.currentState?.validate() == true) {
      print('registering user...');
      await sip.register(usernameController.text,
          forceUdp: true,
          rfc2543Cancel: true,
          proxy: proxyController.text,
          secret: secretController.text);
    }
  }

  destroy() async {
    sip.dispose();
    session.dispose();
    Navigator.of(context).pop();
  }

  Future<dynamic> showIncomingCallDialog(
      String? caller, RTCSessionDescription? jsep) async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Incoming call from ${caller}'),
            actions: [
              ElevatedButton(
                  onPressed: () async {
                    await localMediaSetup();
                    Navigator.of(context, rootNavigator: true)
                        .pop(incomingDialog);
                    Navigator.of(context, rootNavigator: true).pop(callDialog);
                    await sip.accept();
                  },
                  child: Text('Accept')),
              ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context, rootNavigator: true)
                        .pop(incomingDialog);
                    Navigator.of(context, rootNavigator: true).pop(callDialog);
                    await sip.decline();
                  },
                  child: Text('Reject')),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  RTCVideoView(
                    _remoteVideoRenderer,
                    mirror: true,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  )
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            child: IconButton(
                icon: Icon(Icons.refresh),
                color: Colors.white,
                onPressed: () {
                  sip.switchCamera();
                }),
            padding: EdgeInsets.all(25),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            child: CircleAvatar(
                backgroundColor: Colors.red,
                radius: 30,
                child: IconButton(
                    icon: Icon(Icons.call_end),
                    color: Colors.white,
                    onPressed: () async {
                      await sip.hangup();
                      destroy();
                    })),
            padding: EdgeInsets.all(10),
          ),
        )
      ]),
    );
  }

  Future<void> stopTracks() async {
    await stopAllTracksAndDispose(remoteAudioStream);
    await stopAllTracksAndDispose(remoteVideoStream);
  }

  Future<void> cleanUpWebRTCStuff() async {
    await stopTracks();
    _remoteVideoRenderer.srcObject = null;
    _remoteVideoRenderer.dispose();
  }

  @override
  void dispose() async {
    super.dispose();
    cleanUpWebRTCStuff();
  }
}
