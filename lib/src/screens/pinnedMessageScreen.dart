import 'package:connectycube_sdk/connectycube_chat.dart';
import 'package:flutter/material.dart';

class PinnedMessageScreen extends StatefulWidget {
  final CubeUser _cubeUser;
  final CubeDialog _cubeDialog;

  PinnedMessageScreen(this._cubeUser, this._cubeDialog, {Key key})
      : super(key: key);

  @override
  _PinnedMessageScreenState createState() => _PinnedMessageScreenState();
}

class _PinnedMessageScreenState extends State<PinnedMessageScreen> {
  List<CubeMessage> _pinnedMessages;

  Future<List<CubeMessage>> _future;

  @override
  void initState() {
    // TODO: implement initState
     _future=_getMessage();
    print(_future);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Pinned Messages"),
        ),
        body: FutureBuilder(
          future: _future,
          builder: (ctx, dataSnapshot) {
            if (dataSnapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator());
            } else {
              if (dataSnapshot.error != null) {
                return Center(
                  child: Text('An error occurred!'),
                );
              } else {
                return ListView.builder(
                  itemCount: dataSnapshot.data.length,
                  itemBuilder: (ctx, i) => Text("${dataSnapshot.data[i]}"),
                );
              }
            }
          },
        ));
  }

  Future<List<CubeMessage>> _getMessage()  {
    String dialogId = widget._cubeDialog.dialogId;
    GetMessagesParameters params = GetMessagesParameters();
    params.limit = 100;
    params.filters = [RequestFilter("", "", QueryRule.GT, 0)];
    params.markAsRead = true;
    params.sorter = RequestSorter(OrderType.DESC, "", "date_sent");
    return getMessages(dialogId, params.getRequestParameters())
        .then((pagedResult)  {
      print(pagedResult.items[0].body);
      return pagedResult.items.where((message) =>
          widget._cubeDialog.pinnedMessagesIds.contains(message.messageId));
    }).catchError((error) {
      print(error);
    });
  }
}
