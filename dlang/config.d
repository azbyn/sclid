import std.path;

//you probably don't use my signal widget for awesomewm, so you can set this
//to false
enum bool useDbusWidget = false;

//you should probably leave this on.
enum bool checkForNewVersion = true;

enum bool notifyOnLog = true;

private string dir() { return home ~ "/.local/share/sclid"; }
string latexCachePath() { return dir ~"/latex"; }
string attachmentsPath() {
    //you shouldn't change this one as received messages stil go here
    //todo?
    return home ~ "/.local/share/signal-cli/attachments/";
}

string getSignalCliConfigFile(string user) {
    return home ~ "/.local/share/signal-cli/data/"~ user;
}

string pragmaStickerConfigPath() { return dir ~"/pragmaStickers.conf"; }
string pragmaStickerDir() { return dir ~"/pragmaStickers"; }

// enum signalCliPath = "signal-cli";
enum size_t latexDpi = 300;
enum string lineBreakIndicator = "↪";
enum string ellipsis = "…";

enum string w3mimgdisplayPath = "/usr/lib/w3m/w3mimgdisplay";

// TODO this is not encripted; you could read your messages with
// sqlite3 somepath.db; this might be bad. You should store it in memory
// if you don't want someone with access to your computer (even remotely)
// to read your messages
//
// use ":memory:" to store it into memory
// use dir ~ "/history.db" or something similar to store it on disk
auto databasePath() {
    return dir ~ "/history.db";
}

string boxHalfLeft  = "▍";//\u258d
string boxHalfRight = "▌";//\u258c

enum string leftSeparator      = "\uE0B0";//powerline ">" thing (filled triangle)
enum string leftSeparatorThin  = "\uE0B1";//powerline ">" thing (not filled)
enum string rightSeparator     = "\uE0B2";//powerline "<" thing (filled triangle)
enum string rightSeparatorThin = "\uE0B3";//powerline "<" thing (not filled)

//if you use base16 so this is gray, you could use color 19.
//if this doesn't show on your terminal use, 8 - bright black
enum int niceDarkGray256 = 237;//#3a3a3a
// again, if your terminal doesn't support 256 colors, replace with 8
enum int niceLighterGray256 = 240;//#585858

//aka how tall image can be
enum int imageMaxRowsHeight = 9;

enum uint mainScrollOffset = 2;

// if empty it gets read fom $EDITOR
__gshared string editor = "";

import imgDisplay;
// image drawing method - options: NullDisplayer, W3mimgDisplayer, KittyDisplayer
// use NullDisplayer if you don't want images

// TODO at the moment only W3mimgDisplayer with kitty works.
//
// KittyDisplayer isn't properly implemented yet (don't use it, it will freeze
// your terminal)
//
// on other terminals w3mimg produces weird artefacts (at least for the way
// I use it)
alias ImgDisplay = W3mimgDisplayer;

//how much inactivity is needed before we draw the images
//if this is 0, at least with w3m, while scrolling, it's irresponsive
enum uint imgDelayMs = 150;

import std.datetime.date;

//this is in german just for the lolz, you can change them to the english
//counterparts and change "Heute" to "Today";
string shortMonthName(Month m) {
    final switch (m) {
    case Month.jan: return "Jan";
    case Month.feb: return "Feb";
    case Month.mar: return "März";
    case Month.apr: return "Apr";
    case Month.may: return "Mai";
    case Month.jun: return "Juni";
    case Month.jul: return "Juli";
    case Month.aug: return "Aug";
    case Month.sep: return "Sept";
    case Month.oct: return "Oct";
    case Month.nov: return "Nov";
    case Month.dec: return "Dez";
    }
}
string shortWeekDayName(DayOfWeek d) {
    final switch (d) {
    case DayOfWeek.mon: return "Mo";
    case DayOfWeek.tue: return "Di";
    case DayOfWeek.wed: return "Mi";
    case DayOfWeek.thu: return "Do";
    case DayOfWeek.fri: return "Fr";
    case DayOfWeek.sat: return "Sa";
    case DayOfWeek.sun: return "So";
    }
}
enum string todayName = "Heute";


//you shouldn't really modify anything below this:

__gshared {
    string term = "xterm";
    string home;
}

public import theVersion : theVersion;


void init() {
    import std.file, std.range;
    import std.process : environment;

    term = environment["TERM"];
    home = environment["HOME"];
    if (editor.empty) {
        if ("EDITOR" !in environment) editor = "nano";
        else editor = environment["EDITOR"];
    }
    if (term == "xterm-kitty") {
        //you can modify this one
        boxHalfRight = "\u258b";
    }
    mkdirRecurse(dir);
}
