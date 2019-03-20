import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
import 'package:flutter/foundation.dart';

class JMDict {
  Database _db;

  Future<bool> loadDatabase() async {
    var databasesPath = await getDatabasesPath();
    var path = p.join(databasesPath, "jmdict.db");

    // open database if existent
    try {
      _db = await openDatabase(path, readOnly: true);
    } catch (e) {
      debugPrint("Could not open local database: $e");
    }

    if (_db == null) {
      debugPrint("Creating new database from asset.");

      ByteData data = await rootBundle.load(p.join("assets", "jmdict.db"));
      List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await new File(path).writeAsBytes(bytes);

      _db = await openDatabase(path, readOnly: true);
    } else {
      print("Opened existing database ($path).");
    }

    return true;
  }

  Future<bool> hasEntry(String s) async {
    List<Map> kanjiRows = await _db.rawQuery("SELECT wordId FROM kanji WHERE kanji.kanji = ?", [s]);
    List<Map> kanaRows = await _db.rawQuery("SELECT wordId FROM kana WHERE kana.kana = ?", [s]);
    //List<Map> rows = await _db.rawQuery("SELECT kana.wordId FROM kanji INNER JOIN kana ON kanji.wordId = kana.wordId WHERE kanji.kanji = ? OR kana.kana = ?", [s, s]);

    return kanjiRows.length > 0 || kanaRows.length > 0;
  }

  Future<bool> hasEntryStartingWith(String s) async {
    //List<Map> kanjiRows = await _db.rawQuery("SELECT wordId FROM kanji WHERE kanji LIKE ?", [s + "%"]);
    //List<Map> kanaRows = await _db.rawQuery("SELECT wordId FROM kana WHERE kana LIKE ?", [s + "%"]);

    var boundHeader = s.substring(0, s.length - 1);
    var tailerCode = s.codeUnitAt(s.length - 1) + 1;
    var bounder = boundHeader + String.fromCharCode(tailerCode);
    List<Map> kanjiRows = await _db.rawQuery("SELECT wordId FROM kanji WHERE kanji >= ? AND kanji < ?", [s, bounder]); // last character in the last CJK block
    List<Map> kanaRows = await _db.rawQuery("SELECT wordId FROM kana WHERE kana >= ? and kana < ?", [s, bounder]); // last character in the last CJK block

    return kanjiRows.length > 0 || kanaRows.length > 0;
  }

  Future<bool> hasEntryEndingWith(String s) async {

    return true;
  }

  Future<List<Entry>> findEntries(String s) async {
    List<Entry> entries = [];

    // TODO: make this more efficient

    // retrieve all possible word ids
    // TODO: perhaps save related data to avoid repeated queries below
    List<Map> kanjiWordIds = await _db.rawQuery("SELECT wordId FROM kanji WHERE kanji = ?", [s]);
    List<Map> kanaWordIds = await _db.rawQuery("SELECT wordId FROM kana WHERE kana = ?", [s]);

    // filter out duplicates
    var wordIds = <int>{};
    kanjiWordIds.forEach((m) => wordIds.add(m['wordId']));
    kanaWordIds.forEach((m) => wordIds.add(m['wordId']));

    // construct each entry
    for (var wordId in wordIds) {
      var entry = Entry();
      entry.word = s;
      entry.wordId = wordId;

      // compile kana / kanji pairs
      List<Map> kanaRows = await _db.rawQuery("SELECT hasKanji, kana FROM kana WHERE wordId = ?", [wordId]);
      List<Map> kanjiRows = await _db.rawQuery("SELECT kanji FROM kanji WHERE wordId = ?", [wordId]);
      for (var kanaRow in kanaRows) {
        if(kanaRow['hasKanji'] == 1) {
          kanjiRows.forEach((k) => entry.kanji.add(k['kanji']));
          entry.kana[kanaRow['kana']] = true;
        } else {
          entry.kana[kanaRow['kana']] = false;
        }
      }

      // compile senses
      List<Map> senseRows = await _db.rawQuery("SELECT id FROM senses WHERE wordId = ?", [wordId]);
      for (var senseRow in senseRows) {
        var sense = Sense();

        List<Map> glossRows = await _db.rawQuery("SELECT gloss FROM glosses WHERE senseId = ?", [senseRow['id']]);
        glossRows.forEach((g) => sense.glosses.add(g['gloss']));

        // TODO: subqery
        List<Map> posIdRows = await _db.rawQuery("SELECT posId FROM sense_pos WHERE senseId = ?", [senseRow['id']]);
        for(var posIdRow in posIdRows) {
          List<Map> posRows = await _db.rawQuery("SELECT type FROM pos WHERE id = ?", [posIdRow['posId']]);
          if(posRows.length == 1) {
            sense.partsOfSpeech.add(posRows[0]['type']);
          }
        }
        entry.senses.add(sense);
      }
      entries.add(entry);
    }
    return entries;
  }

}

class Entry {
  int wordId;
  String word;
  Map<String, bool> kana; // kana, hasKanji
  Set<String> kanji;
  List<Sense> senses;

  Entry() {
    kana = Map();
    kanji = {};
    senses = [];
  }

  @override
  String toString() {
    var s = "$word: ";
    kana.forEach((kana, hasKanji) {
      if (hasKanji) {
        s += "$kana (${kanji.join(", ")}). ";
      } else {
        s += "$kana. ";
      }
    });
    senses.forEach((sense) => s += "Sense (${sense.partsOfSpeech}): ${sense.glosses}. ");

    return s;
  }
}

class Sense {
  List<String> glosses;
  List<String> partsOfSpeech;

  Sense() {
    glosses = [];
    partsOfSpeech = [];
  }
}