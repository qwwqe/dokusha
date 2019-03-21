import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;
import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert' as convert;
import 'package:flutter/gestures.dart';
import 'jmdict.dart';

void main() => runApp(MainApp());

class MainApp extends StatefulWidget {
  @override
  _MainAppState createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  JMDict jmdict;

  @override
  void initState(){
    super.initState();
    jmdict = JMDict();
    jmdict.loadDatabase().then((v) {}); // TODO: loading dialog or something
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (context) => HomePage(title: 'Japanese Reader', jmdict: jmdict),
        '/view': (context) => ViewPage(jmdict: jmdict),
      },
      title: 'Japanese Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}

class ViewPage extends StatefulWidget {
  final String content;
  final JMDict jmdict;

  ViewPage({Key key, this.content, this.jmdict}) : super(key: key);

  @override
  _ViewPageState createState() => _ViewPageState();
}

class _ViewPageState extends State<ViewPage> {
  // TODO: implement more efficient text selection tracking (i.e. not a 1-1 map)
  List<bool> textSelected;
  int textSize = 0;
  ScrollController scrollController;

  final List<double> textSizes = [14, 18];

  @override
  void initState() {
    super.initState();
    textSelected = List.filled(widget.content.length, false);
    scrollController = ScrollController(keepScrollOffset: true);
  }

  @override
  Widget build(BuildContext context) {
    var textList = <TextSpan>[];
    for (var i = 0; i < widget.content.length; i++) {
      textList.add(TextSpan(
        text: widget.content[i],
        style: TextStyle(
          background: Paint()
            ..color = textSelected[i] ? Colors.blue : Colors.transparent,
          fontSize: textSizes[textSize],
        ),
        recognizer: new TapGestureRecognizer()
          ..onTap = () {
            _findSelectedEntries(i).then((entries) {
              debugPrint(entries.toString());
              setState(() {

                if(entries.length > 0) {
                  for(var j = 0; j < entries[0].word.length; j++) {
                    textSelected[i + j] = true;
                  }
                } else if (widget.content[i].trim().isNotEmpty) {
                  textSelected[i] = true;
                }
              });

              if(entries.length > 0) {
                _showDictModal(entries);
              } else {
                Timer(Duration(milliseconds: 300), () => _clearSelectedText());
              }
            });
          },
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
        actions: <Widget>[
          IconButton(
              icon: Icon(Icons.format_size),
              onPressed: () => setState(
                    () => textSize == 0 ? textSize = 1 : textSize = 0,
              )),
        ],
      ),
      body: SingleChildScrollView(
        child: RichText(
          text: TextSpan(
            style: TextStyle(color: Colors.black),
            children: textList,
          ),
        ),
        controller: scrollController,
      ),
    );
  }

  void _showDictModal(List<Entry> entries) {
    Future<void> future =
    showModalBottomSheet(context: context, builder: (c) => DictModal(entries: entries));
    future.then((v) => _clearSelectedText());
  }

  void _clearSelectedText() {
    setState(() => textSelected.fillRange(0, textSelected.length, false));
  }

  Future<List<Entry>> _findSelectedEntries(int offset) async {
    // If any string of characters in content starting from offset exist in the
    // dictionary, return the entries corresponding to the longest such string.
    // Otherwise, return the entries corresponding to the string with the longest
    // prefix before this offset, if this exists.
    // If neither of these exist, return an empty list.

    // Forward search
    var stopwatch = Stopwatch();
    stopwatch.start();
    var lastBound = offset;
    var hasStarting = await widget.jmdict.hasEntryStartingWith(widget.content[offset]);
    for(var i = offset + 1; i < widget.content.length && hasStarting; i++) {
      var word = widget.content.substring(offset, i);
      debugPrint("Searching for prefix: $word.");
      if (await widget.jmdict.hasEntry(word)) {
        lastBound = i;
        debugPrint("Full word found.");
      }
      hasStarting = await widget.jmdict.hasEntryStartingWith(word);
      if(hasStarting) {
        debugPrint("Prefix found.");
      }
    }
    stopwatch.stop();
    debugPrint("Search took ${stopwatch.elapsed}.");
    debugPrint("${lastBound - offset}");

    // String found in forward search
    if(lastBound > offset) {
      stopwatch.reset();
      stopwatch.start();
      var word = widget.content.substring(offset, lastBound);
      List<Entry> entries = await widget.jmdict.findEntries(word);
      debugPrint("Retreiving ${entries.length} entries took ${stopwatch.elapsed}.");
      stopwatch.stop();
      return entries;
    }

    // TODO: Backward search

    return [];
  }
}

class DictModal extends StatefulWidget {
  final List<Entry> entries;

  DictModal({Key key, this.entries}) : super(key: key);

  @override
  _DictModalState createState() => _DictModalState();
}

class _DictModalState extends State<DictModal> {
  int entry;

  @override
  void initState() {
    super.initState();
    entry = 0;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(5),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.entries[entry].word,
                    style: DefaultTextStyle
                        .of(context)
                        .style
                        .apply(fontSizeFactor: 1.5, fontWeightDelta: 2),
                  ),
                  IconButton(
                      icon: Icon(Icons.arrow_forward_ios),
                      iconSize: 30,
                      onPressed: () =>
                          setState(
                                () =>
                            entry < widget.entries.length - 1
                                ? entry += 1
                                : entry,
                          )),
                ]),
            Chip(
              avatar: CircleAvatar(
                backgroundColor: Colors.purpleAccent,
                child: Text("音"),
              ),
              backgroundColor: Colors.transparent,
              label: Text(widget.entries[entry].kana.keys.join(",")),
            ),
            Chip(
              avatar: CircleAvatar(
                backgroundColor: Colors.purpleAccent,
                child: Text("漢"),
              ),
              backgroundColor: Colors.transparent,
              label: Text(widget.entries[entry].kanji.join(",")),
            ),
            ListView(
              scrollDirection: Axis.vertical,
              shrinkWrap: true,
              children: List<Widget>.from(widget.entries[entry].senses.map((sense) {
                return Text("(${sense.partsOfSpeech.join(",")}): ${sense.glosses.join(",")}");
              })),
            ),
          ]
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  HomePage({Key key, this.title, this.jmdict}) : super(key: key);

  final String title;
  final JMDict jmdict;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            RaisedButton(
              child: const Text('Open Clipboard'),
              onPressed: () {
                Future<ClipboardData> data =
                Clipboard.getData(Clipboard.kTextPlain);

                data.then((d) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewPage(content: d.text, jmdict: jmdict),
                    ),
                  );
                });
              },
            ),
            Builder(builder: (BuildContext context) {
              return RaisedButton(
                child: const Text('Open File'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewPage(content: 'file', jmdict: jmdict),
                    ),
                  );
                },
              );
            }),
            Builder(
              builder: (BuildContext context) {
                return RaisedButton(
                  child: const Text('Open Url From Clipboard'),
                  onPressed: () {
                    Scaffold.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Loading URL..."),
                      ),
                    );
                    Future<ClipboardData> data =
                    Clipboard.getData(Clipboard.kTextPlain);

                    data.then((d) {
                      debugPrint(d.text);
                      Future<http.Response> resp = http.get(d.text);

                      resp.then((r) {
                        if (r.statusCode != 200) {
                          Scaffold.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Failed to load URL."),
                            ),
                          );
                          return;
                        }

                        String text = "";
                        var document = parser.parse(convert.utf8.decode(r.bodyBytes));
                        Queue<dom.Node> queue = Queue();

                        document.nodes.forEach((n) {
                          queue.add(n);
                        });

                        while (queue.length > 0) {
                          dom.Node node = queue.removeFirst();

                          if (node.nodeType == dom.Node.TEXT_NODE) {
                            if (node.text.trim() != "") {
                              text = text + node.text + "\n\n";
                            }
                            continue;
                          }

                          node.nodes.forEach((n) {
                            var name = n.parent.localName;
                            if (name == 'script' ||
                                name == 'noscript' ||
                                name == 'style') {
                              return;
                            }
                            queue.add(n);
                          });
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ViewPage(content: text, jmdict: jmdict),
                          ),
                        );
                      });
                    });
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
