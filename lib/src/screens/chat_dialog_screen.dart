import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:connectycube_sdk/connectycube_sdk.dart';
import 'package:connectycube_sdk/src/chat/models/message_status_model.dart';
import 'package:connectycube_sdk/src/chat/models/typing_status_model.dart';
import 'package:swipe_to/swipe_to.dart';
import 'chat_details_screen.dart';
import '../utils/consts.dart';
import '../widgets/common.dart';
import '../widgets/full_photo.dart';
import '../widgets/loading.dart';

class ChatDialogScreen extends StatefulWidget {
  final CubeUser _cubeUser;
  CubeDialog _cubeDialog;

  ChatDialogScreen(
    this._cubeUser,
    this._cubeDialog,
  );

  @override
  _ChatDialogScreenState createState() => _ChatDialogScreenState();
}

class _ChatDialogScreenState extends State<ChatDialogScreen> {
  static AppBar _appBar;
  bool _messageSelected = false;
  CubeMessage _message;

  @override
  void initState() {
    // TODO: implement initState

    super.initState();
  }

  Widget _setAppBar() {
    setState(() {
      _appBar = AppBar(
        title: Text(
          widget._cubeDialog.name != null ? widget._cubeDialog.name : '',
        ),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            onPressed: () => _chatDetails(context),
            icon: Icon(
              Icons.info_outline,
              color: Colors.white,
            ),
          ),
        ],
      );
    });

    return _appBar;
  }

  Widget _modifyAppBar() {
    setState(() {
      _appBar = AppBar(
        actions: [
          IconButton(
              onPressed: () async {
                List<String> ids = [_message.messageId];
                bool force =
                    true; // true - to delete everywhere, false - to delete for himself
                setState(() {
                  _messageSelected = false;
                });
                await deleteMessages(ids, force).then((deleteItemsResult) {
                  print(deleteItemsResult);
                  print(deleteItemsResult.successfullyDeleted);
                }).catchError((error) {});
              },
              icon: Icon(Icons.delete)),
          IconButton(
            onPressed: _pinnedMessages(_message.messageId),
            icon: widget._cubeDialog.pinnedMessagesIds
                    .contains(_message.messageId)
                ? Icon(Icons.push_pin_sharp)
                : Icon(Icons.push_pin_outlined),
          )
        ],
      );
    });

    return _appBar;
  }

  @override
  Widget build(BuildContext context) {
    log("||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||");
    print(_messageSelected);
    log("||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||");
    return Scaffold(
      appBar: _messageSelected ? _modifyAppBar() : _setAppBar(),
      body: ChatScreen(widget._cubeUser, widget._cubeDialog,
          (CubeMessage message) {
        setState(() {
          _messageSelected = !_messageSelected;
          _message = message;
        });
        _modifyAppBar();
        log("///////////////////////////////////////////////");
        print(_messageSelected);
        log("///////////////////////////////////////////////");
        // _modifyAppBar();
      }),
    );
  }

  _pinnedMessages(String msgID) {
    List<String> pinned = widget._cubeDialog.pinnedMessagesIds;
    UpdateDialogParams updateDialogParams = UpdateDialogParams();
    if (pinned.contains(_message.messageId)) {
      setState(() {
        _message.properties["Pinned"] = "false";
        _messageSelected = false;
      });
      updateDialogParams.deletePinnedMsgIds = [_message.messageId].toSet();
      pinned.remove(_message.messageId);
    } else {
      setState(() {
        _message.properties["Pinned"] = "true";
        _messageSelected = false;
      });
      pinned.add(_message.messageId);
      updateDialogParams.addPinnedMsgIds = [_message.messageId].toSet();
    }
    updateDialog(widget._cubeDialog.dialogId,
            updateDialogParams.getUpdateDialogParams())
        .then((dialog) {
      widget._cubeDialog = dialog;
      // setState(() {
      //   _body = ChatScreen(widget._cubeUser, dialog, (CubeMessage message) {
      //     _messageSelected = !_messageSelected;
      //     _message = message;
      //     _modifyAppBar(message);
      //   });
      // });
    });
  }

  _chatDetails(BuildContext context) async {
    log("_chatDetails= ${widget._cubeDialog}");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ChatDetailsScreen(widget._cubeUser, widget._cubeDialog),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  static const String TAG = "_CreateChatScreenState";
  final CubeUser _cubeUser;
  final CubeDialog _cubeDialog;
  final Function(CubeMessage) _modifyAppBar;

  ChatScreen(this._cubeUser, this._cubeDialog, this._modifyAppBar);

  @override
  State createState() => ChatScreenState(_cubeUser, _cubeDialog, _modifyAppBar);
}

class ChatScreenState extends State<ChatScreen> {
  CubeMessage _replyMessage;
  final CubeUser _cubeUser;
  final CubeDialog _cubeDialog;
  final Function(CubeMessage) _modifyAppBar;
  final Map<int, CubeUser> _occupants = Map();
  File imageFile;
  final picker = ImagePicker();
  bool isLoading;
  String imageUrl;
  List<CubeMessage> listMessage = [];
  Timer typingTimer;
  bool isTyping = false;
  String userStatus = '';
  final TextEditingController textEditingController = TextEditingController();
  final ScrollController listScrollController = ScrollController();
  StreamSubscription<CubeMessage> msgSubscription;
  StreamSubscription<MessageStatus> deliveredSubscription;
  StreamSubscription<MessageStatus> readSubscription;
  StreamSubscription<TypingStatus> typingSubscription;
  List<CubeMessage> _unreadMessages = [];
  List<CubeMessage> _unsentMessages = [];

  bool _isReplying = false;

  ChatScreenState(this._cubeUser, this._cubeDialog, this._modifyAppBar);

  @override
  void initState() {
    super.initState();
    _initCubeChat();
    isLoading = false;
    imageUrl = '';
  }

  @override
  void dispose() {
    msgSubscription?.cancel();
    deliveredSubscription?.cancel();
    readSubscription?.cancel();
    typingSubscription?.cancel();
    textEditingController?.dispose();
    super.dispose();
  }

  void openGallery() async {
    final pickedFile = await picker.getImage(source: ImageSource.gallery);
    if (pickedFile == null) return;
    setState(() {
      isLoading = true;
    });
    imageFile = File(pickedFile.path);
    uploadImageFile();
  }

  Future uploadImageFile() async {
    uploadFile(imageFile, isPublic: true, onProgress: (progress) {
      log("uploadImageFile progress= $progress");
    }).then((cubeFile) {
      var url = cubeFile.getPublicUrl();
      onSendChatAttachment(url);
    }).catchError((ex) {
      setState(() {
        isLoading = false;
      });
      Fluttertoast.showToast(msg: 'This file is not an image');
    });
  }

  void onReceiveMessage(CubeMessage message) {
    log("onReceiveMessage message= $message");
    if (message.dialogId != _cubeDialog.dialogId ||
        message.senderId == _cubeUser.id) return;
    _cubeDialog.readMessage(message);
    addMessageToListView(message);
  }

  void onDeliveredMessage(MessageStatus status) {
    log("onDeliveredMessage message= $status");
    updateReadDeliveredStatusMessage(status, false);
  }

  void onReadMessage(MessageStatus status) {
    log("onReadMessage message= ${status.messageId}");
    updateReadDeliveredStatusMessage(status, true);
  }

  void onTypingMessage(TypingStatus status) {
    log("TypingStatus message= ${status.userId}");
    if (status.userId == _cubeUser.id ||
        (status.dialogId != null && status.dialogId != _cubeDialog.dialogId))
      return;
    userStatus = _occupants[status.userId]?.fullName ??
        _occupants[status.userId]?.login ??
        '';
    if (userStatus.isEmpty) return;
    userStatus = "$userStatus is typing ...";
    if (isTyping != true) {
      setState(() {
        isTyping = true;
      });
    }
    startTypingTimer();
  }

  startTypingTimer() {
    typingTimer?.cancel();
    typingTimer = Timer(Duration(milliseconds: 900), () {
      setState(() {
        isTyping = false;
      });
    });
  }

  void onSendChatMessage(String content) {
    if (content.trim() != '') {
      final message = createCubeMsg();
      message.body = content.trim();
      onSendMessage(message);
    } else {
      Fluttertoast.showToast(msg: 'Nothing to send');
    }
  }

  void onSendChatAttachment(String url) async {
    var decodedImage = await decodeImageFromList(imageFile.readAsBytesSync());
    final attachment = CubeAttachment();
    attachment.id = imageFile.hashCode.toString();
    attachment.type = CubeAttachmentType.IMAGE_TYPE;
    attachment.url = url;
    attachment.height = decodedImage.height;
    attachment.width = decodedImage.width;
    final message = createCubeMsg();
    message.body = "Attachment";
    message.attachments = [attachment];
    onSendMessage(message);
  }

  CubeMessage createCubeMsg() {
    var message = CubeMessage();
    message.dateSent = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    message.markable = true;
    message.saveToHistory = true;
    return message;
  }

  void onSendMessage(CubeMessage message) async {
    log("onSendMessage message= $message");
    textEditingController.clear();
    message.properties["Pinned"] = "false";

    message.properties["isReplying"] = _isReplying ? "true" : "false";
    message.properties["isReplyingbody"] =
        _isReplying ? "${_replyMessage.body}" : "";
    message.properties["isReplyingsenderId"] =
        _isReplying ? "${_replyMessage.senderId}" : "";
    message.properties["isReplyingmessageId"] =
        _isReplying ? "${_replyMessage.messageId}" : "";
    setState(() {
      _isReplying = false;
      _replyMessage = null;
    });
    await _cubeDialog.sendMessage(message);
    message.senderId = _cubeUser.id;
    addMessageToListView(message);
    listScrollController.animateTo(0.0,
        duration: Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  updateReadDeliveredStatusMessage(MessageStatus status, bool isRead) {
    CubeMessage msg = listMessage.firstWhere(
        (msg) => msg.messageId == status.messageId,
        orElse: () => null);
    if (msg == null) return;
    if (isRead)
      msg.readIds == null
          ? msg.readIds = [status.userId]
          : msg.readIds?.add(status.userId);
    else
      msg.deliveredIds == null
          ? msg.deliveredIds = [status.userId]
          : msg.deliveredIds?.add(status.userId);
    setState(() {});
  }

  addMessageToListView(CubeMessage message) {
    setState(() {
      isLoading = false;
      int existMessageIndex = listMessage.indexWhere((cubeMessage) {
        return cubeMessage.messageId == message.messageId;
      });
      if (existMessageIndex != -1) {
        listMessage
            .replaceRange(existMessageIndex, existMessageIndex + 1, [message]);
      } else {
        listMessage.insert(0, message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              // List of messages
              buildListMessage(),
              //Typing content
              buildTyping(),
              // Input content
              if (_isReplying) buildReply(),
              buildInput(),
            ],
          ),
          // Loading
          buildLoading()
        ],
      ),
      onWillPop: onBackPress,
    );
  }

  Widget buildItem(int index, CubeMessage message) {
    markAsReadIfNeed() {
      var isOpponentMsgRead =
          message.readIds != null && message.readIds.contains(_cubeUser.id);
      print(
          "markAsReadIfNeed message= ${message}, isOpponentMsgRead= $isOpponentMsgRead");
      if (message.senderId != _cubeUser.id && !isOpponentMsgRead) {
        if (message.readIds == null) {
          message.readIds = [_cubeUser.id];
        } else {
          message.readIds.add(_cubeUser.id);
        }
        if (CubeChatConnection.instance.chatConnectionState ==
            CubeChatConnectionState.Ready) {
          _cubeDialog.readMessage(message);
        } else {
          _unreadMessages.add(message);
        }
      }
    }

    Widget getReadDeliveredWidget() {
      bool messageIsRead() {
        if (_cubeDialog.type == CubeDialogType.PRIVATE)
          return message.readIds != null &&
              (message.recipientId == null ||
                  message.readIds.contains(message.recipientId));
        return message.readIds != null &&
            message.readIds.any((int id) => _occupants.keys.contains(id));
      }

      bool messageIsDelivered() {
        if (_cubeDialog.type == CubeDialogType.PRIVATE)
          return message.deliveredIds?.contains(message.recipientId) ?? false;
        return message.deliveredIds != null &&
            message.deliveredIds.any((int id) => _occupants.keys.contains(id));
      }

      if (messageIsRead())
        return Stack(children: <Widget>[
          Icon(
            Icons.check,
            size: 15.0,
            color: blueColor,
          ),
          Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(
              Icons.check,
              size: 15.0,
              color: blueColor,
            ),
          )
        ]);
      else if (messageIsDelivered()) {
        return Stack(children: <Widget>[
          Icon(
            Icons.check,
            size: 15.0,
            color: greyColor,
          ),
          Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(
              Icons.check,
              size: 15.0,
              color: greyColor,
            ),
          )
        ]);
      } else {
        return Icon(
          Icons.check,
          size: 15.0,
          color: greyColor,
        );
      }
    }

    Widget getDateWidget() {
      return Text(
        DateFormat('HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(message.dateSent * 1000)),
        style: TextStyle(
            color: greyColor, fontSize: 12.0, fontStyle: FontStyle.italic),
      );
    }

    Widget getHeaderDateWidget() {
      return Container(
        alignment: Alignment.center,
        child: Text(
          DateFormat('dd MMMM').format(
              DateTime.fromMillisecondsSinceEpoch(message.dateSent * 1000)),
          style: TextStyle(
              color: primaryColor, fontSize: 20.0, fontStyle: FontStyle.italic),
        ),
        margin: EdgeInsets.all(10.0),
      );
    }

    bool isHeaderView() {
      int headerId = int.parse(DateFormat('ddMMyyyy').format(
          DateTime.fromMillisecondsSinceEpoch(message.dateSent * 1000)));
      if (index >= listMessage.length - 1) {
        return false;
      }
      var msgPrev = listMessage[index + 1];
      int nextItemHeaderId = int.parse(DateFormat('ddMMyyyy').format(
          DateTime.fromMillisecondsSinceEpoch(msgPrev.dateSent * 1000)));
      var result = headerId != nextItemHeaderId;
      return result;
    }

    if (message.senderId == _cubeUser.id) {
      // print(
      //     "***********************************************************************pinned 2******************************************************");
      // print(message.properties);
      // Right (own message)
      return Column(
        children: <Widget>[
          isHeaderView() ? getHeaderDateWidget() : SizedBox.shrink(),
          // Added by chinmay for reply to message
          SwipeTo(
            onRightSwipe: () {
              setState(() {
                _replyMessage = message;
                _isReplying = true;
              });
            },
            child: InkWell(
              onLongPress: () => _modifyAppBar(message),
              child: Row(
                children: <Widget>[
                  message.attachments?.isNotEmpty ?? false
                      // Image
                      ? Container(
                          child: FlatButton(
                            child: Material(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    CachedNetworkImage(
                                      placeholder: (context, url) => Container(
                                        child: CircularProgressIndicator(
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  themeColor),
                                        ),
                                        width: 200.0,
                                        height: 200.0,
                                        padding: EdgeInsets.all(70.0),
                                        decoration: BoxDecoration(
                                          color: greyColor2,
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(8.0),
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Material(
                                        child: Image.asset(
                                          'images/img_not_available.jpeg',
                                          width: 200.0,
                                          height: 200.0,
                                          fit: BoxFit.cover,
                                        ),
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8.0),
                                        ),
                                        clipBehavior: Clip.hardEdge,
                                      ),
                                      imageUrl: message.attachments.first.url,
                                      width: 200.0,
                                      height: 200.0,
                                      fit: BoxFit.cover,
                                    ),
                                    getDateWidget(),
                                    getReadDeliveredWidget(),
                                  ]),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8.0)),
                              clipBehavior: Clip.hardEdge,
                            ),
                            onPressed: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => FullPhoto(
                                          url: message.attachments.first.url)));
                            },
                            padding: EdgeInsets.all(0),
                          ),
                          margin: EdgeInsets.only(
                              bottom: isLastMessageRight(index) ? 20.0 : 10.0,
                              right: 10.0),
                        )
                      : message.body != null && message.body.isNotEmpty
                          // Text
                          ? Flexible(
                              child: Container(
                                padding:
                                    EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                                decoration: BoxDecoration(
                                    color: greyColor2,
                                    borderRadius: BorderRadius.circular(8.0)),
                                margin: EdgeInsets.only(
                                    bottom:
                                        isLastMessageRight(index) ? 20.0 : 10.0,
                                    right: 10.0),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (message.properties["isReplying"] ==
                                          "true")
                                        Container(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                int.parse(message.properties[
                                                            "isReplyingsenderId"]) ==
                                                        _cubeUser.id
                                                    ? "You"
                                                    : _occupants[int.parse(message
                                                                .properties[
                                                            "isReplyingsenderId"])]
                                                        .fullName,
                                                style: TextStyle(
                                                    color: greyColor3),
                                              ),
                                              Text(
                                                message.properties[
                                                    "isReplyingbody"],
                                                style: TextStyle(
                                                    color: greyColor3),
                                              )
                                            ],
                                          ),
                                          margin: EdgeInsets.only(
                                              bottom: isLastMessageRight(index)
                                                  ? 20.0
                                                  : 10.0,
                                              right: 10.0),
                                          padding: EdgeInsets.fromLTRB(
                                              15.0, 10.0, 15.0, 10.0),
                                          decoration: BoxDecoration(
                                            color: primaryColor,
                                            borderRadius:
                                                BorderRadius.circular(8.0),
                                          ),
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            message.body,
                                            style:
                                                TextStyle(color: primaryColor),
                                          ),
                                          if (message.properties["Pinned"] ==
                                              "true")
                                            Icon(
                                              Icons.push_pin_sharp,
                                              size: 20,
                                            ),
                                        ],
                                      ),
                                      getDateWidget(),
                                      getReadDeliveredWidget(),
                                    ]),
                              ),
                            )
                          : Container(
                              child: Text(
                                "Empty",
                                style: TextStyle(color: primaryColor),
                              ),
                              padding:
                                  EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                              width: 200.0,
                              decoration: BoxDecoration(
                                  color: greyColor2,
                                  borderRadius: BorderRadius.circular(8.0)),
                              margin: EdgeInsets.only(
                                  bottom:
                                      isLastMessageRight(index) ? 20.0 : 10.0,
                                  right: 10.0),
                            ),
                ],
                mainAxisAlignment: MainAxisAlignment.end,
              ),
            ),
          ),
        ],
      );
    } else {
      // print(
      //     "***********************************************************************pinned******************************************************");
      // print(message.properties);
      // Left (opponent message)
      markAsReadIfNeed();
      return Container(
        child: Column(
          children: <Widget>[
            isHeaderView() ? getHeaderDateWidget() : SizedBox.shrink(),
            // Added by Chinmay for reply to message
            SwipeTo(
              onRightSwipe: () {
                setState(() {
                  _replyMessage = message;
                  _isReplying = true;
                });
              },
              child: InkWell(
                onLongPress: () => _modifyAppBar(message),
                child: Row(
                  children: <Widget>[
                    Material(
                      child: CircleAvatar(
                        backgroundImage: _occupants[message.senderId]?.avatar !=
                                    null &&
                                _occupants[message.senderId].avatar.isNotEmpty
                            ? NetworkImage(_occupants[message.senderId].avatar)
                            : null,
                        backgroundColor: greyColor2,
                        radius: 30,
                        child: getAvatarTextWidget(
                          _occupants[message.senderId]?.avatar != null &&
                              _occupants[message.senderId].avatar.isNotEmpty,
                          _occupants[message.senderId]
                              ?.fullName
                              ?.substring(0, 2)
                              ?.toUpperCase(),
                        ),
                      ),
                      borderRadius: BorderRadius.all(
                        Radius.circular(18.0),
                      ),
                      clipBehavior: Clip.hardEdge,
                    ),
                    message.attachments?.isNotEmpty ?? false
                        ? Container(
                            child: FlatButton(
                              child: Material(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CachedNetworkImage(
                                        placeholder: (context, url) =>
                                            Container(
                                          child: CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    themeColor),
                                          ),
                                          width: 200.0,
                                          height: 200.0,
                                          padding: EdgeInsets.all(70.0),
                                          decoration: BoxDecoration(
                                            color: greyColor2,
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(8.0),
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) =>
                                            Material(
                                          child: Image.asset(
                                            'images/img_not_available.jpeg',
                                            width: 200.0,
                                            height: 200.0,
                                            fit: BoxFit.cover,
                                          ),
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(8.0),
                                          ),
                                          clipBehavior: Clip.hardEdge,
                                        ),
                                        imageUrl: message.attachments.first.url,
                                        width: 200.0,
                                        height: 200.0,
                                        fit: BoxFit.cover,
                                      ),
                                      getDateWidget(),
                                    ]),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(8.0)),
                                clipBehavior: Clip.hardEdge,
                              ),
                              onPressed: () {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => FullPhoto(
                                            url: message
                                                .attachments.first.url)));
                              },
                              padding: EdgeInsets.all(0),
                            ),
                            margin: EdgeInsets.only(left: 10.0),
                          )
                        : message.body != null && message.body.isNotEmpty
                            ? Flexible(
                                child: Container(
                                  padding: EdgeInsets.fromLTRB(
                                      15.0, 10.0, 15.0, 10.0),
                                  decoration: BoxDecoration(
                                      color: primaryColor,
                                      borderRadius: BorderRadius.circular(8.0)),
                                  margin: EdgeInsets.only(left: 10.0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (message.properties["isReplying"] ==
                                            "true")
                                          Container(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _occupants[int.parse(message
                                                                .properties[
                                                            "isReplyingsenderId"])]
                                                        .fullName,
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: primaryColor),
                                                  ),
                                                  Text(
                                                    message.properties[
                                                        "isReplyingbody"],
                                                    style: TextStyle(
                                                        color: primaryColor),
                                                  )
                                                ],
                                              ),
                                              margin: EdgeInsets.only(
                                                  bottom:
                                                      isLastMessageRight(index)
                                                          ? 20.0
                                                          : 10.0,
                                                  right: 10.0),
                                              padding: EdgeInsets.fromLTRB(
                                                  15.0, 10.0, 15.0, 10.0),
                                              decoration: BoxDecoration(
                                                  color: greyColor3,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          8.0))),

                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              message.body,
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                            if (message.properties["Pinned"] ==
                                                "true")
                                              Icon(
                                                Icons.push_pin_sharp,
                                                size: 20,
                                                color: greyColor3,
                                              ),
                                          ],
                                        ),
                                        // if (_cubeDialog.pinnedMessagesIds
                                        //     .contains(message.messageId))

                                        getDateWidget(),
                                      ]),
                                ),
                              )
                            : Container(
                                child: Text(
                                  "Empty",
                                  style: TextStyle(color: primaryColor),
                                ),
                                padding:
                                    EdgeInsets.fromLTRB(15.0, 10.0, 15.0, 10.0),
                                width: 200.0,
                                decoration: BoxDecoration(
                                    color: greyColor2,
                                    borderRadius: BorderRadius.circular(8.0)),
                                margin: EdgeInsets.only(
                                    bottom:
                                        isLastMessageRight(index) ? 20.0 : 10.0,
                                    right: 10.0),
                              ),
                  ],
                ),
              ),
            ),
          ],
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
        margin: EdgeInsets.only(bottom: 10.0),
      );
    }
  }

  bool isLastMessageLeft(int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1].id == _cubeUser.id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }

  bool isLastMessageRight(int index) {
    if ((index > 0 &&
            listMessage != null &&
            listMessage[index - 1].id != _cubeUser.id) ||
        index == 0) {
      return true;
    } else {
      return false;
    }
  }

  Widget buildLoading() {
    return Positioned(
      child: isLoading ? const Loading() : Container(),
    );
  }

  Widget buildTyping() {
    return Visibility(
      visible: isTyping,
      child: Container(
        child: Text(
          userStatus,
          style: TextStyle(color: primaryColor),
        ),
        alignment: Alignment.centerLeft,
        margin: EdgeInsets.all(16.0),
      ),
    );
  }

  Widget buildInput() {
    return Container(
      child: Row(
        children: <Widget>[
          // Button send image
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 1.0),
              child: IconButton(
                icon: Icon(Icons.image),
                onPressed: () {
                  openGallery();
                },
                color: primaryColor,
              ),
            ),
            color: Colors.white,
          ),
          // Edit text
          Flexible(
            child: Container(
              child: TextField(
                style: TextStyle(color: primaryColor, fontSize: 15.0),
                controller: textEditingController,
                decoration: InputDecoration.collapsed(
                  hintText: 'Type your message...',
                  hintStyle: TextStyle(color: greyColor),
                ),
                onChanged: (text) {
                  _cubeDialog.sendIsTypingStatus();
                },
              ),
            ),
          ),
          // Button send message
          Material(
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 8.0),
              child: IconButton(
                icon: Icon(Icons.send),
                onPressed: () => onSendChatMessage(textEditingController.text),
                color: primaryColor,
              ),
            ),
            color: Colors.white,
          ),
        ],
      ),
      width: double.infinity,
      height: 50.0,
      decoration: BoxDecoration(
          border: Border(top: BorderSide(color: greyColor2, width: 0.5)),
          color: Colors.white),
    );
  }

  // Added by Chinmay for reply to message
  Widget buildReplyMessage() {
    if (_isReplying)
      return IntrinsicHeight(
          child: Row(
        children: [
          Container(
            color: Colors.green,
            width: 4,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        int.parse(_replyMessage
                                    .properties["isReplyingsenderId"]) ==
                                _cubeUser.id
                            ? "You"
                            : "${_occupants[_replyMessage.senderId].fullName}",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ),
                    GestureDetector(
                      child: Icon(Icons.close, size: 16),
                      onTap: () {
                        setState(() {
                          _replyMessage = null;
                          _isReplying = false;
                        });
                      },
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Text("${_replyMessage.body}",
                    style: TextStyle(color: Colors.black87)),
              ],
            ),
          ),
        ],
      ));
  }

  // Added by Chinmay for reply to message
  Widget buildReply() => Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(24),
          ),
        ),
        child: buildReplyMessage(),
      );

  Widget buildListMessage() {
    getWidgetMessages(listMessage) {
      return ListView.builder(
        padding: EdgeInsets.all(10.0),
        itemBuilder: (context, index) => buildItem(index, listMessage[index]),
        itemCount: listMessage.length,
        reverse: true,
        controller: listScrollController,
      );
    }

    if (listMessage != null && listMessage.isNotEmpty) {
      return Flexible(child: getWidgetMessages(listMessage));
    }
    return Flexible(
      child: StreamBuilder(
        stream: getAllItems().asStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(themeColor)));
          } else {
            listMessage = snapshot.data;
            return getWidgetMessages(listMessage);
          }
        },
      ),
    );
  }

  Future<List<CubeMessage>> getAllItems() async {
    Completer<List<CubeMessage>> completer = Completer();
    List<CubeMessage> messages;
    var params = GetMessagesParameters();
    params.sorter = RequestSorter(SORT_DESC, '', 'date_sent');
    try {
      await Future.wait<void>([
        getMessages(_cubeDialog.dialogId, params.getRequestParameters())
            .then((result) => messages = result.items),
        getAllUsersByIds(_cubeDialog.occupantsIds.toSet()).then((result) =>
            _occupants.addAll(Map.fromIterable(result.items,
                key: (item) => item.id, value: (item) => item)))
      ]);
      completer.complete(messages);
    } catch (error) {
      completer.completeError(error);
    }
    return completer.future;
  }

  Future<bool> onBackPress() {
    return Navigator.pushNamedAndRemoveUntil(
        context, 'select_dialog', (r) => false,
        arguments: {USER_ARG_NAME: _cubeUser});
  }

  _initChatListeners() {
    msgSubscription = CubeChatConnection
        .instance.chatMessagesManager.chatMessagesStream
        .listen(onReceiveMessage);
    deliveredSubscription = CubeChatConnection
        .instance.messagesStatusesManager.deliveredStream
        .listen(onDeliveredMessage);
    readSubscription = CubeChatConnection
        .instance.messagesStatusesManager.readStream
        .listen(onReadMessage);
    typingSubscription = CubeChatConnection
        .instance.typingStatusesManager.isTypingStream
        .listen(onTypingMessage);
  }

  void _initCubeChat() {
    if (CubeChatConnection.instance.isAuthenticated()) {
      _initChatListeners();
    } else {
      CubeChatConnection.instance.connectionStateStream.listen((state) {
        if (CubeChatConnectionState.Ready == state) {
          _initChatListeners();
          if (_unreadMessages.isNotEmpty) {
            _unreadMessages.forEach((cubeMessage) {
              _cubeDialog.readMessage(cubeMessage);
            });
            _unreadMessages.clear();
          }
          if (_unsentMessages.isNotEmpty) {
            _unsentMessages.forEach((cubeMessage) {
              _cubeDialog.sendMessage(cubeMessage);
            });
            _unsentMessages.clear();
          }
        }
      });
    }
  }
}
