use strict;
use warnings;
local $/;
my $text = <>;

sub replace_required {
    my ($from, $to) = @_;
    my $count = ($text =~ s/\Q$from\E/$to/g);
    die "Required UI layout source fragment was not found: $from\n" unless $count;
}

replace_required('ihatemeetings 1.5', 'ihatemeetings 1.5.2');

# Main window: larger canvas with wider controls and larger row gaps.
replace_required('width:390,height:382', 'width:520,height:500');
replace_required('place(advancedCheck,12,348,150)', 'place(advancedCheck,16,462,180)');
replace_required('place(configureButton,292,346,86)', 'place(configureButton,404,456,100)');
replace_required('place(adapterBox,12,315,286)', 'place(adapterBox,16,420,380)');
replace_required('place(refreshButton,301,315,78)', 'place(refreshButton,404,420,100)');
replace_required('place(modeBox,12,285,366)', 'place(modeBox,16,380,488)');
replace_required('place(behaviorBox,12,255,366)', 'place(behaviorBox,16,340,488)');
replace_required('place(randomCheck,12,229,150)', 'place(randomCheck,16,300,170)');
replace_required('label("Min / fixed (ms)",171,232,104)', 'label("Min / fixed (ms)",200,303,130)');
replace_required('label("Max (ms)",291,232,85)', 'label("Max (ms)",360,303,100)');
replace_required('label("Offline",12,205,100)', 'label("Offline",16,263,100)');
replace_required('place(offField,171,200,99)', 'place(offField,200,258,140)');
replace_required('place(offMax,283,200,95)', 'place(offMax,360,258,144)');
replace_required('label("Online",12,176,100)', 'label("Online",16,223,100)');
replace_required('place(onField,171,171,99)', 'place(onField,200,218,140)');
replace_required('place(onMax,283,171,95)', 'place(onMax,360,218,144)');
replace_required('label("Cycles",12,147,48)', 'label("Cycles",16,183,48)');
replace_required('place(countField,63,143,65)', 'place(countField,70,178,90)');
replace_required('place(unlimitedCheck,143,143,122)', 'place(unlimitedCheck,180,178,140)');
replace_required('label("Limit s",268,147,49)', 'label("Limit s",340,183,62)');
replace_required('place(limitField,319,143,59)', 'place(limitField,410,178,94)');
replace_required('label("Hotkey",12,117,47)', 'label("Hotkey",16,143,47)');
replace_required('place(hotKeyBox,63,112,231)', 'place(hotKeyBox,70,138,320)');
replace_required('place(testButton,300,112,78)', 'place(testButton,404,138,100)');
replace_required('place(startButton,12,78,179,30)', 'place(startButton,16,92,238,30)');
replace_required('place(stopButton,199,78,179,30)', 'place(stopButton,266,92,238,30)');
replace_required('place(statusLabel,12,51,366,21)', 'place(statusLabel,16,60,488,21)');
replace_required('place(detailLabel,12,8,366,40)', 'place(detailLabel,16,12,488,42)');

# Advanced editor: larger window with roomier field and inspector rows.
replace_required('width:620,height:410', 'width:760,height:530');
replace_required('add(pb,70,370,130)', 'add(pb,82,486,150)');
replace_required('lab("Preset",12,374,55)', 'lab("Preset",16,491,58)');
replace_required('add(af,88,334,410)', 'add(af,96,442,520)');
replace_required('add(browse,506,334,102)', 'add(browse,626,442,118)');
replace_required('lab("Application",12,339,74)', 'lab("Application",16,447,78)');
replace_required('add(proto,80,298,110)', 'add(proto,90,394,132)');
replace_required('lab("Protocol",12,303,62)', 'lab("Protocol",16,399,66)');
replace_required('add(dir,282,298,130)', 'add(dir,316,394,150)');
replace_required('lab("Direction",211,303,67)', 'lab("Direction",244,399,68)');
replace_required('add(lp,510,298,98)', 'add(lp,636,394,108)');
replace_required('lab("Local port",435,303,70)', 'lab("Local port",560,399,72)');
replace_required('add(rf,116,262,290)', 'add(rf,128,346,430)');
replace_required('lab("Remote IP/CIDR",12,267,100)', 'lab("Remote IP/CIDR",16,351,108)');
replace_required('add(rp,510,262,98)', 'add(rp,636,346,108)');
replace_required('lab("Remote port",425,267,80)', 'lab("Remote port",556,351,80)');
replace_required('add(identify,12,222,150)', 'add(identify,16,298,170)');
replace_required('add(use,170,222,180)', 'add(use,196,298,200)');
replace_required('add(flows,12,182,596)', 'add(flows,16,250,728)');
replace_required('add(note,12,116,596,54)', 'add(note,16,156,728,74)');
replace_required('add(save,414,70,94,28)', 'add(save,534,96,100,30)');
replace_required('add(close,514,70,94,28)', 'add(close,644,96,100,30)');

# Keep the existing compiler-normalization pass used by the 1.5 source.
$text =~ s/\s*==\s*/ == /g;
$text =~ s/\s*!=\s*/ != /g;
$text =~ s/&&!/&& !/g;
$text =~ s/\|\|!/|| !/g;

print $text;
