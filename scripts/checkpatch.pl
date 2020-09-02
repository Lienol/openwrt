#!/usr/bin/env perl 
# (c) 2001, Dave Jones. (the file handling bit)
# (c) 2005, Joel Schopp <jschopp@austin.ibm.com> (the ugly bit)
# (c) 2007,2008, Andy Whitcroft <apw@uk.ibm.com> (new conditions, test suite)
# (c) 2008-2010 Andy Whitcroft <apw@canonical.com>
# (c) 2013 Vasilis Tsiligiannis <acinonyx@openwrt.gr> (adapt for OpenWrt tree)
# Licensed under the terms of the GNU GPL License version 2

use strict;
use warnings;

my $P = $0;
$P =~ s@.*/@@g;

my $V = '0.32-openwrt';

use Getopt::Long qw(:config no_auto_abbrev);

my $quiet = 0;
my $tree = 1;
my $chk_signoff = 1;
my $chk_patch = 1;
my $tst_only;
my $emacs = 0;
my $terse = 0;
my $file = 0;
my $check = 0;
my $summary = 1;
my $mailback = 0;
my $summary_file = 0;
my $show_types = 0;
my $root;
my %debug;
my %ignore_type = ();
my @ignore = ();
my $help = 0;
my $configuration_file = ".checkpatch.conf";

sub help {
	my ($exitcode) = @_;

	print << "EOM";
Usage: $P [OPTION]... [FILE]...
Version: $V

Options:
  -q, --quiet                quiet
  --no-tree                  run without a kernel tree
  --no-signoff               do not check for 'Signed-off-by' line
  --patch                    treat FILE as patchfile (default)
  --emacs                    emacs compile window format
  --terse                    one line per report
  -f, --file                 treat FILE as regular source file
  --subjective, --strict     enable more subjective tests
  --ignore TYPE(,TYPE2...)   ignore various comma separated message types
  --show-types               show the message "types" in the output
  --root=PATH                PATH to the kernel tree root
  --no-summary               suppress the per-file summary
  --mailback                 only produce a report in case of warnings/errors
  --summary-file             include the filename in summary
  --debug KEY=[0|1]          turn on/off debugging of KEY, where KEY is one of
                             'values', 'possible', 'type', and 'attr' (default
                             is all off)
  --test-only=WORD           report only warnings/errors containing WORD
                             literally
  -h, --help, --version      display this help and exit

When FILE is - read standard input.
EOM

	exit($exitcode);
}

my $conf = which_conf($configuration_file);
if (-f $conf) {
	my @conf_args;
	open(my $conffile, '<', "$conf")
	    or warn "$P: Can't find a readable $configuration_file file $!\n";

	while (<$conffile>) {
		my $line = $_;

		$line =~ s/\s*\n?$//g;
		$line =~ s/^\s*//g;
		$line =~ s/\s+/ /g;

		next if ($line =~ m/^\s*#/);
		next if ($line =~ m/^\s*$/);

		my @words = split(" ", $line);
		foreach my $word (@words) {
			last if ($word =~ m/^#/);
			push (@conf_args, $word);
		}
	}
	close($conffile);
	unshift(@ARGV, @conf_args) if @conf_args;
}

GetOptions(
	'q|quiet+'	=> \$quiet,
	'tree!'		=> \$tree,
	'signoff!'	=> \$chk_signoff,
	'patch!'	=> \$chk_patch,
	'emacs!'	=> \$emacs,
	'terse!'	=> \$terse,
	'f|file!'	=> \$file,
	'subjective!'	=> \$check,
	'strict!'	=> \$check,
	'ignore=s'	=> \@ignore,
	'show-types!'	=> \$show_types,
	'root=s'	=> \$root,
	'summary!'	=> \$summary,
	'mailback!'	=> \$mailback,
	'summary-file!'	=> \$summary_file,

	'debug=s'	=> \%debug,
	'test-only=s'	=> \$tst_only,
	'h|help'	=> \$help,
	'version'	=> \$help
) or help(1);

help(0) if ($help);

my $exit = 0;

if ($#ARGV < 0) {
	print "$P: no input files\n";
	exit(1);
}

@ignore = split(/,/, join(',',@ignore));
foreach my $word (@ignore) {
	$word =~ s/\s*\n?$//g;
	$word =~ s/^\s*//g;
	$word =~ s/\s+/ /g;
	$word =~ tr/[a-z]/[A-Z]/;

	next if ($word =~ m/^\s*#/);
	next if ($word =~ m/^\s*$/);

	$ignore_type{$word}++;
}

my $dbg_values = 0;
my $dbg_possible = 0;
my $dbg_type = 0;
my $dbg_attr = 0;
for my $key (keys %debug) {
	## no critic
	eval "\${dbg_$key} = '$debug{$key}';";
	die "$@" if ($@);
}

my $rpt_cleaners = 0;

if ($terse) {
	$emacs = 1;
	$quiet++;
}

if ($tree) {
	if (defined $root) {
		if (!top_of_openwrt_tree($root)) {
			die "$P: $root: --root does not point at a valid tree\n";
		}
	} else {
		if (top_of_openwrt_tree('.')) {
			$root = '.';
		} elsif ($0 =~ m@(.*)/scripts/[^/]*$@ &&
						top_of_openwrt_tree($1)) {
			$root = $1;
		}
	}

	if (!defined $root) {
		print "Must be run from the top-level dir. of a OpenWrt tree\n";
		exit(2);
	}
}

my $emitted_corrupt = 0;

our $Ident	= qr{
			[A-Za-z_][A-Za-z\d_]*
			(?:\s*\#\#\s*[A-Za-z_][A-Za-z\d_]*)*
		}x;
our $Storage	= qr{extern|static|asmlinkage};
our $Sparse	= qr{
			__user|
			__kernel|
			__force|
			__iomem|
			__must_check|
			__init_refok|
			__kprobes|
			__ref|
			__rcu
		}x;

# Notes to $Attribute:
# We need \b after 'init' otherwise 'initconst' will cause a false positive in a check
our $Attribute	= qr{
			const|
			__percpu|
			__nocast|
			__safe|
			__bitwise__|
			__packed__|
			__packed2__|
			__naked|
			__maybe_unused|
			__always_unused|
			__noreturn|
			__used|
			__cold|
			__noclone|
			__deprecated|
			__read_mostly|
			__kprobes|
			__(?:mem|cpu|dev|)(?:initdata|initconst|init\b)|
			____cacheline_aligned|
			____cacheline_aligned_in_smp|
			____cacheline_internodealigned_in_smp|
			__weak
		  }x;
our $Modifier;
our $Inline	= qr{inline|__always_inline|noinline};
our $Member	= qr{->$Ident|\.$Ident|\[[^]]*\]};
our $Lval	= qr{$Ident(?:$Member)*};

our $Constant	= qr{(?i:(?:[0-9]+|0x[0-9a-f]+)[ul]*)};
our $Assignment	= qr{(?:\*\=|/=|%=|\+=|-=|<<=|>>=|&=|\^=|\|=|=)};
our $Compare    = qr{<=|>=|==|!=|<|>};
our $Operators	= qr{
			<=|>=|==|!=|
			=>|->|<<|>>|<|>|!|~|
			&&|\|\||,|\^|\+\+|--|&|\||\+|-|\*|\/|%
		  }x;

our $NonptrType;
our $Type;
our $Declare;

our $NON_ASCII_UTF8	= qr{
	[\xC2-\xDF][\x80-\xBF]               # non-overlong 2-byte
	|  \xE0[\xA0-\xBF][\x80-\xBF]        # excluding overlongs
	| [\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}  # straight 3-byte
	|  \xED[\x80-\x9F][\x80-\xBF]        # excluding surrogates
	|  \xF0[\x90-\xBF][\x80-\xBF]{2}     # planes 1-3
	| [\xF1-\xF3][\x80-\xBF]{3}          # planes 4-15
	|  \xF4[\x80-\x8F][\x80-\xBF]{2}     # plane 16
}x;

our $UTF8	= qr{
	[\x09\x0A\x0D\x20-\x7E]              # ASCII
	| $NON_ASCII_UTF8
}x;

our $typeTypedefs = qr{(?x:
	(?:__)?(?:u|s|be|le)(?:8|16|32|64)|
	atomic_t
)};

our $logFunctions = qr{(?x:
	printk(?:_ratelimited|_once|)|
	[a-z0-9]+_(?:printk|emerg|alert|crit|err|warning|warn|notice|info|debug|dbg|vdbg|devel|cont|WARN)(?:_ratelimited|_once|)|
	WARN(?:_RATELIMIT|_ONCE|)|
	panic|
	MODULE_[A-Z_]+
)};

our $signature_tags = qr{(?xi:
	Signed-off-by:|
	Acked-by:|
	Tested-by:|
	Reviewed-by:|
	Reported-by:|
	To:|
	Cc:
)};

our @typeList = (
	qr{void},
	qr{(?:unsigned\s+)?char},
	qr{(?:unsigned\s+)?short},
	qr{(?:unsigned\s+)?int},
	qr{(?:unsigned\s+)?long},
	qr{(?:unsigned\s+)?long\s+int},
	qr{(?:unsigned\s+)?long\s+long},
	qr{(?:unsigned\s+)?long\s+long\s+int},
	qr{unsigned},
	qr{float},
	qr{double},
	qr{bool},
	qr{struct\s+$Ident},
	qr{union\s+$Ident},
	qr{enum\s+$Ident},
	qr{${Ident}_t},
	qr{${Ident}_handler},
	qr{${Ident}_handler_fn},
);
our @modifierList = (
	qr{fastcall},
);

our $allowed_asm_includes = qr{(?x:
	irq|
	memory
)};
# memory.h: ARM has a custom one

sub build_types {
	my $mods = "(?x:  \n" . join("|\n  ", @modifierList) . "\n)";
	my $all = "(?x:  \n" . join("|\n  ", @typeList) . "\n)";
	$Modifier	= qr{(?:$Attribute|$Sparse|$mods)};
	$NonptrType	= qr{
			(?:$Modifier\s+|const\s+)*
			(?:
				(?:typeof|__typeof__)\s*\([^\)]*\)|
				(?:$typeTypedefs\b)|
				(?:${all}\b)
			)
			(?:\s+$Modifier|\s+const)*
		  }x;
	$Type	= qr{
			$NonptrType
			(?:(?:\s|\*|\[\])+\s*const|(?:\s|\*|\[\])+|(?:\s*\[\s*\])+)?
			(?:\s+$Inline|\s+$Modifier)*
		  }x;
	$Declare	= qr{(?:$Storage\s+)?$Type};
}
build_types();


our $Typecast	= qr{\s*(\(\s*$NonptrType\s*\)){0,1}\s*};

# Using $balanced_parens, $LvalOrFunc, or $FuncArg
# requires at least perl version v5.10.0
# Any use must be runtime checked with $^V

our $balanced_parens = qr/(\((?:[^\(\)]++|(?-1))*\))/;
our $LvalOrFunc	= qr{($Lval)\s*($balanced_parens{0,1})\s*};
our $FuncArg = qr{$Typecast{0,1}($LvalOrFunc|$Constant)};

sub deparenthesize {
	my ($string) = @_;
	return "" if (!defined($string));
	$string =~ s@^\s*\(\s*@@g;
	$string =~ s@\s*\)\s*$@@g;
	$string =~ s@\s+@ @g;
	return $string;
}

$chk_signoff = 0 if ($file);

my @rawlines = ();
my @lines = ();
my $vname;
for my $filename (@ARGV) {
	my $FILE;
	if ($file) {
		open($FILE, '-|', "diff -u /dev/null $filename") ||
			die "$P: $filename: diff failed - $!\n";
	} elsif ($filename eq '-') {
		open($FILE, '<&STDIN');
	} else {
		open($FILE, '<', "$filename") ||
			die "$P: $filename: open failed - $!\n";
	}
	if ($filename eq '-') {
		$vname = 'Your patch';
	} else {
		$vname = $filename;
	}
	while (<$FILE>) {
		chomp;
		push(@rawlines, $_);
	}
	close($FILE);
	if (!process($filename)) {
		$exit = 1;
	}
	@rawlines = ();
	@lines = ();
}

exit($exit);

sub top_of_openwrt_tree {
	my ($root) = @_;

	my @tree_check = (
		"BSDmakefile", "Config.in", "LICENSE", "Makefile", "README.md",
		"feeds.conf.default", "include", "package", "rules.mk",
		"scripts", "target", "toolchain", "tools"
	);

	foreach my $check (@tree_check) {
		if (! -e $root . '/' . $check) {
			return 0;
		}
	}
	return 1;
    }

sub parse_email {
	my ($formatted_email) = @_;

	my $name = "";
	my $address = "";
	my $comment = "";

	if ($formatted_email =~ /^(.*)<(\S+\@\S+)>(.*)$/) {
		$name = $1;
		$address = $2;
		$comment = $3 if defined $3;
	} elsif ($formatted_email =~ /^\s*<(\S+\@\S+)>(.*)$/) {
		$address = $1;
		$comment = $2 if defined $2;
	} elsif ($formatted_email =~ /(\S+\@\S+)(.*)$/) {
		$address = $1;
		$comment = $2 if defined $2;
		$formatted_email =~ s/$address.*$//;
		$name = $formatted_email;
		$name =~ s/^\s+|\s+$//g;
		$name =~ s/^\"|\"$//g;
		# If there's a name left after stripping spaces and
		# leading quotes, and the address doesn't have both
		# leading and trailing angle brackets, the address
		# is invalid. ie:
		#   "joe smith joe@smith.com" bad
		#   "joe smith <joe@smith.com" bad
		if ($name ne "" && $address !~ /^<[^>]+>$/) {
			$name = "";
			$address = "";
			$comment = "";
		}
	}

	$name =~ s/^\s+|\s+$//g;
	$name =~ s/^\"|\"$//g;
	$address =~ s/^\s+|\s+$//g;
	$address =~ s/^\<|\>$//g;

	if ($name =~ /[^\w \-]/i) { ##has "must quote" chars
		$name =~ s/(?<!\\)"/\\"/g; ##escape quotes
		$name = "\"$name\"";
	}

	return ($name, $address, $comment);
}

sub format_email {
	my ($name, $address) = @_;

	my $formatted_email;

	$name =~ s/^\s+|\s+$//g;
	$name =~ s/^\"|\"$//g;
	$address =~ s/^\s+|\s+$//g;

	if ($name =~ /[^\w \-]/i) { ##has "must quote" chars
		$name =~ s/(?<!\\)"/\\"/g; ##escape quotes
		$name = "\"$name\"";
	}

	if ("$name" eq "") {
		$formatted_email = "$address";
	} else {
		$formatted_email = "$name <$address>";
	}

	return $formatted_email;
}

sub which_conf {
	my ($conf) = @_;

	foreach my $path (split(/:/, ".:$ENV{HOME}:.scripts")) {
		if (-e "$path/$conf") {
			return "$path/$conf";
		}
	}

	return "";
}

sub expand_tabs {
	my ($str) = @_;

	my $res = '';
	my $n = 0;
	for my $c (split(//, $str)) {
		if ($c eq "\t") {
			$res .= ' ';
			$n++;
			for (; ($n % 8) != 0; $n++) {
				$res .= ' ';
			}
			next;
		}
		$res .= $c;
		$n++;
	}

	return $res;
}
sub copy_spacing {
	(my $res = shift) =~ tr/\t/ /c;
	return $res;
}

sub line_stats {
	my ($line) = @_;

	# Drop the diff line leader and expand tabs
	$line =~ s/^.//;
	$line = expand_tabs($line);

	# Pick the indent from the front of the line.
	my ($white) = ($line =~ /^(\s*)/);

	return (length($line), length($white));
}

my $sanitise_quote = '';

sub sanitise_line_reset {
	my ($in_comment) = @_;

	if ($in_comment) {
		$sanitise_quote = '*/';
	} else {
		$sanitise_quote = '';
	}
}
sub sanitise_line {
	my ($line) = @_;

	my $res = '';
	my $l = '';

	my $qlen = 0;
	my $off = 0;
	my $c;

	# Always copy over the diff marker.
	$res = substr($line, 0, 1);

	for ($off = 1; $off < length($line); $off++) {
		$c = substr($line, $off, 1);

		# Comments we are wacking completly including the begin
		# and end, all to $;.
		if ($sanitise_quote eq '' && substr($line, $off, 2) eq '/*') {
			$sanitise_quote = '*/';

			substr($res, $off, 2, "$;$;");
			$off++;
			next;
		}
		if ($sanitise_quote eq '*/' && substr($line, $off, 2) eq '*/') {
			$sanitise_quote = '';
			substr($res, $off, 2, "$;$;");
			$off++;
			next;
		}
		if ($sanitise_quote eq '' && substr($line, $off, 2) eq '//') {
			$sanitise_quote = '//';

			substr($res, $off, 2, $sanitise_quote);
			$off++;
			next;
		}

		# A \ in a string means ignore the next character.
		if (($sanitise_quote eq "'" || $sanitise_quote eq '"') &&
		    $c eq "\\") {
			substr($res, $off, 2, 'XX');
			$off++;
			next;
		}
		# Regular quotes.
		if ($c eq "'" || $c eq '"') {
			if ($sanitise_quote eq '') {
				$sanitise_quote = $c;

				substr($res, $off, 1, $c);
				next;
			} elsif ($sanitise_quote eq $c) {
				$sanitise_quote = '';
			}
		}

		#print "c<$c> SQ<$sanitise_quote>\n";
		if ($off != 0 && $sanitise_quote eq '*/' && $c ne "\t") {
			substr($res, $off, 1, $;);
		} elsif ($off != 0 && $sanitise_quote eq '//' && $c ne "\t") {
			substr($res, $off, 1, $;);
		} elsif ($off != 0 && $sanitise_quote && $c ne "\t") {
			substr($res, $off, 1, 'X');
		} else {
			substr($res, $off, 1, $c);
		}
	}

	if ($sanitise_quote eq '//') {
		$sanitise_quote = '';
	}

	# The pathname on a #include may be surrounded by '<' and '>'.
	if ($res =~ /^.\s*\#\s*include\s+\<(.*)\>/) {
		my $clean = 'X' x length($1);
		$res =~ s@\<.*\>@<$clean>@;

	# The whole of a #error is a string.
	} elsif ($res =~ /^.\s*\#\s*(?:error|warning)\s+(.*)\b/) {
		my $clean = 'X' x length($1);
		$res =~ s@(\#\s*(?:error|warning)\s+).*@$1$clean@;
	}

	return $res;
}

sub ctx_statement_block {
	my ($linenr, $remain, $off) = @_;
	my $line = $linenr - 1;
	my $blk = '';
	my $soff = $off;
	my $coff = $off - 1;
	my $coff_set = 0;

	my $loff = 0;

	my $type = '';
	my $level = 0;
	my @stack = ();
	my $p;
	my $c;
	my $len = 0;

	my $remainder;
	while (1) {
		@stack = (['', 0]) if ($#stack == -1);

		#warn "CSB: blk<$blk> remain<$remain>\n";
		# If we are about to drop off the end, pull in more
		# context.
		if ($off >= $len) {
			for (; $remain > 0; $line++) {
				last if (!defined $lines[$line]);
				next if ($lines[$line] =~ /^-/);
				$remain--;
				$loff = $len;
				$blk .= $lines[$line] . "\n";
				$len = length($blk);
				$line++;
				last;
			}
			# Bail if there is no further context.
			#warn "CSB: blk<$blk> off<$off> len<$len>\n";
			if ($off >= $len) {
				last;
			}
			if ($level == 0 && substr($blk, $off) =~ /^.\s*#\s*define/) {
				$level++;
				$type = '#';
			}
		}
		$p = $c;
		$c = substr($blk, $off, 1);
		$remainder = substr($blk, $off);

		#warn "CSB: c<$c> type<$type> level<$level> remainder<$remainder> coff_set<$coff_set>\n";

		# Handle nested #if/#else.
		if ($remainder =~ /^#\s*(?:ifndef|ifdef|if)\s/) {
			push(@stack, [ $type, $level ]);
		} elsif ($remainder =~ /^#\s*(?:else|elif)\b/) {
			($type, $level) = @{$stack[$#stack - 1]};
		} elsif ($remainder =~ /^#\s*endif\b/) {
			($type, $level) = @{pop(@stack)};
		}

		# Statement ends at the ';' or a close '}' at the
		# outermost level.
		if ($level == 0 && $c eq ';') {
			last;
		}

		# An else is really a conditional as long as its not else if
		if ($level == 0 && $coff_set == 0 &&
				(!defined($p) || $p =~ /(?:\s|\}|\+)/) &&
				$remainder =~ /^(else)(?:\s|{)/ &&
				$remainder !~ /^else\s+if\b/) {
			$coff = $off + length($1) - 1;
			$coff_set = 1;
			#warn "CSB: mark coff<$coff> soff<$soff> 1<$1>\n";
			#warn "[" . substr($blk, $soff, $coff - $soff + 1) . "]\n";
		}

		if (($type eq '' || $type eq '(') && $c eq '(') {
			$level++;
			$type = '(';
		}
		if ($type eq '(' && $c eq ')') {
			$level--;
			$type = ($level != 0)? '(' : '';

			if ($level == 0 && $coff < $soff) {
				$coff = $off;
				$coff_set = 1;
				#warn "CSB: mark coff<$coff>\n";
			}
		}
		if (($type eq '' || $type eq '{') && $c eq '{') {
			$level++;
			$type = '{';
		}
		if ($type eq '{' && $c eq '}') {
			$level--;
			$type = ($level != 0)? '{' : '';

			if ($level == 0) {
				if (substr($blk, $off + 1, 1) eq ';') {
					$off++;
				}
				last;
			}
		}
		# Preprocessor commands end at the newline unless escaped.
		if ($type eq '#' && $c eq "\n" && $p ne "\\") {
			$level--;
			$type = '';
			$off++;
			last;
		}
		$off++;
	}
	# We are truly at the end, so shuffle to the next line.
	if ($off == $len) {
		$loff = $len + 1;
		$line++;
		$remain--;
	}

	my $statement = substr($blk, $soff, $off - $soff + 1);
	my $condition = substr($blk, $soff, $coff - $soff + 1);

	#warn "STATEMENT<$statement>\n";
	#warn "CONDITION<$condition>\n";

	#print "coff<$coff> soff<$off> loff<$loff>\n";

	return ($statement, $condition,
			$line, $remain + 1, $off - $loff + 1, $level);
}

sub statement_lines {
	my ($stmt) = @_;

	# Strip the diff line prefixes and rip blank lines at start and end.
	$stmt =~ s/(^|\n)./$1/g;
	$stmt =~ s/^\s*//;
	$stmt =~ s/\s*$//;

	my @stmt_lines = ($stmt =~ /\n/g);

	return $#stmt_lines + 2;
}

sub statement_rawlines {
	my ($stmt) = @_;

	my @stmt_lines = ($stmt =~ /\n/g);

	return $#stmt_lines + 2;
}

sub statement_block_size {
	my ($stmt) = @_;

	$stmt =~ s/(^|\n)./$1/g;
	$stmt =~ s/^\s*{//;
	$stmt =~ s/}\s*$//;
	$stmt =~ s/^\s*//;
	$stmt =~ s/\s*$//;

	my @stmt_lines = ($stmt =~ /\n/g);
	my @stmt_statements = ($stmt =~ /;/g);

	my $stmt_lines = $#stmt_lines + 2;
	my $stmt_statements = $#stmt_statements + 1;

	if ($stmt_lines > $stmt_statements) {
		return $stmt_lines;
	} else {
		return $stmt_statements;
	}
}

sub ctx_statement_full {
	my ($linenr, $remain, $off) = @_;
	my ($statement, $condition, $level);

	my (@chunks);

	# Grab the first conditional/block pair.
	($statement, $condition, $linenr, $remain, $off, $level) =
				ctx_statement_block($linenr, $remain, $off);
	#print "F: c<$condition> s<$statement> remain<$remain>\n";
	push(@chunks, [ $condition, $statement ]);
	if (!($remain > 0 && $condition =~ /^\s*(?:\n[+-])?\s*(?:if|else|do)\b/s)) {
		return ($level, $linenr, @chunks);
	}

	# Pull in the following conditional/block pairs and see if they
	# could continue the statement.
	for (;;) {
		($statement, $condition, $linenr, $remain, $off, $level) =
				ctx_statement_block($linenr, $remain, $off);
		#print "C: c<$condition> s<$statement> remain<$remain>\n";
		last if (!($remain > 0 && $condition =~ /^(?:\s*\n[+-])*\s*(?:else|do)\b/s));
		#print "C: push\n";
		push(@chunks, [ $condition, $statement ]);
	}

	return ($level, $linenr, @chunks);
}

sub ctx_block_get {
	my ($linenr, $remain, $outer, $open, $close, $off) = @_;
	my $line;
	my $start = $linenr - 1;
	my $blk = '';
	my @o;
	my @c;
	my @res = ();

	my $level = 0;
	my @stack = ($level);
	for ($line = $start; $remain > 0; $line++) {
		next if ($rawlines[$line] =~ /^-/);
		$remain--;

		$blk .= $rawlines[$line];

		# Handle nested #if/#else.
		if ($lines[$line] =~ /^.\s*#\s*(?:ifndef|ifdef|if)\s/) {
			push(@stack, $level);
		} elsif ($lines[$line] =~ /^.\s*#\s*(?:else|elif)\b/) {
			$level = $stack[$#stack - 1];
		} elsif ($lines[$line] =~ /^.\s*#\s*endif\b/) {
			$level = pop(@stack);
		}

		foreach my $c (split(//, $lines[$line])) {
			##print "C<$c>L<$level><$open$close>O<$off>\n";
			if ($off > 0) {
				$off--;
				next;
			}

			if ($c eq $close && $level > 0) {
				$level--;
				last if ($level == 0);
			} elsif ($c eq $open) {
				$level++;
			}
		}

		if (!$outer || $level <= 1) {
			push(@res, $rawlines[$line]);
		}

		last if ($level == 0);
	}

	return ($level, @res);
}
sub ctx_block_outer {
	my ($linenr, $remain) = @_;

	my ($level, @r) = ctx_block_get($linenr, $remain, 1, '{', '}', 0);
	return @r;
}
sub ctx_block {
	my ($linenr, $remain) = @_;

	my ($level, @r) = ctx_block_get($linenr, $remain, 0, '{', '}', 0);
	return @r;
}
sub ctx_statement {
	my ($linenr, $remain, $off) = @_;

	my ($level, @r) = ctx_block_get($linenr, $remain, 0, '(', ')', $off);
	return @r;
}
sub ctx_block_level {
	my ($linenr, $remain) = @_;

	return ctx_block_get($linenr, $remain, 0, '{', '}', 0);
}
sub ctx_statement_level {
	my ($linenr, $remain, $off) = @_;

	return ctx_block_get($linenr, $remain, 0, '(', ')', $off);
}

sub ctx_locate_comment {
	my ($first_line, $end_line) = @_;

	# Catch a comment on the end of the line itself.
	my ($current_comment) = ($rawlines[$end_line - 1] =~ m@.*(/\*.*\*/)\s*(?:\\\s*)?$@);
	return $current_comment if (defined $current_comment);

	# Look through the context and try and figure out if there is a
	# comment.
	my $in_comment = 0;
	$current_comment = '';
	for (my $linenr = $first_line; $linenr < $end_line; $linenr++) {
		my $line = $rawlines[$linenr - 1];
		#warn "           $line\n";
		if ($linenr == $first_line and $line =~ m@^.\s*\*@) {
			$in_comment = 1;
		}
		if ($line =~ m@/\*@) {
			$in_comment = 1;
		}
		if (!$in_comment && $current_comment ne '') {
			$current_comment = '';
		}
		$current_comment .= $line . "\n" if ($in_comment);
		if ($line =~ m@\*/@) {
			$in_comment = 0;
		}
	}

	chomp($current_comment);
	return($current_comment);
}
sub ctx_has_comment {
	my ($first_line, $end_line) = @_;
	my $cmt = ctx_locate_comment($first_line, $end_line);

	##print "LINE: $rawlines[$end_line - 1 ]\n";
	##print "CMMT: $cmt\n";

	return ($cmt ne '');
}

sub raw_line {
	my ($linenr, $cnt) = @_;

	my $offset = $linenr - 1;
	$cnt++;

	my $line;
	while ($cnt) {
		$line = $rawlines[$offset++];
		next if (defined($line) && $line =~ /^-/);
		$cnt--;
	}

	return $line;
}

sub cat_vet {
	my ($vet) = @_;
	my ($res, $coded);

	$res = '';
	while ($vet =~ /([^[:cntrl:]]*)([[:cntrl:]]|$)/g) {
		$res .= $1;
		if ($2 ne '') {
			$coded = sprintf("^%c", unpack('C', $2) + 64);
			$res .= $coded;
		}
	}
	$res =~ s/$/\$/;

	return $res;
}

my $av_preprocessor = 0;
my $av_pending;
my @av_paren_type;
my $av_pend_colon;

sub annotate_reset {
	$av_preprocessor = 0;
	$av_pending = '_';
	@av_paren_type = ('E');
	$av_pend_colon = 'O';
}

sub annotate_values {
	my ($stream, $type) = @_;

	my $res;
	my $var = '_' x length($stream);
	my $cur = $stream;

	print "$stream\n" if ($dbg_values > 1);

	while (length($cur)) {
		@av_paren_type = ('E') if ($#av_paren_type < 0);
		print " <" . join('', @av_paren_type) .
				"> <$type> <$av_pending>" if ($dbg_values > 1);
		if ($cur =~ /^(\s+)/o) {
			print "WS($1)\n" if ($dbg_values > 1);
			if ($1 =~ /\n/ && $av_preprocessor) {
				$type = pop(@av_paren_type);
				$av_preprocessor = 0;
			}

		} elsif ($cur =~ /^(\(\s*$Type\s*)\)/ && $av_pending eq '_') {
			print "CAST($1)\n" if ($dbg_values > 1);
			push(@av_paren_type, $type);
			$type = 'c';

		} elsif ($cur =~ /^($Type)\s*(?:$Ident|,|\)|\(|\s*$)/) {
			print "DECLARE($1)\n" if ($dbg_values > 1);
			$type = 'T';

		} elsif ($cur =~ /^($Modifier)\s*/) {
			print "MODIFIER($1)\n" if ($dbg_values > 1);
			$type = 'T';

		} elsif ($cur =~ /^(\#\s*define\s*$Ident)(\(?)/o) {
			print "DEFINE($1,$2)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;
			push(@av_paren_type, $type);
			if ($2 ne '') {
				$av_pending = 'N';
			}
			$type = 'E';

		} elsif ($cur =~ /^(\#\s*(?:undef\s*$Ident|include\b))/o) {
			print "UNDEF($1)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;
			push(@av_paren_type, $type);

		} elsif ($cur =~ /^(\#\s*(?:ifdef|ifndef|if))/o) {
			print "PRE_START($1)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;

			push(@av_paren_type, $type);
			push(@av_paren_type, $type);
			$type = 'E';

		} elsif ($cur =~ /^(\#\s*(?:else|elif))/o) {
			print "PRE_RESTART($1)\n" if ($dbg_values > 1);
			$av_preprocessor = 1;

			push(@av_paren_type, $av_paren_type[$#av_paren_type]);

			$type = 'E';

		} elsif ($cur =~ /^(\#\s*(?:endif))/o) {
			print "PRE_END($1)\n" if ($dbg_values > 1);

			$av_preprocessor = 1;

			# Assume all arms of the conditional end as this
			# one does, and continue as if the #endif was not here.
			pop(@av_paren_type);
			push(@av_paren_type, $type);
			$type = 'E';

		} elsif ($cur =~ /^(\\\n)/o) {
			print "PRECONT($1)\n" if ($dbg_values > 1);

		} elsif ($cur =~ /^(__attribute__)\s*\(?/o) {
			print "ATTR($1)\n" if ($dbg_values > 1);
			$av_pending = $type;
			$type = 'N';

		} elsif ($cur =~ /^(sizeof)\s*(\()?/o) {
			print "SIZEOF($1)\n" if ($dbg_values > 1);
			if (defined $2) {
				$av_pending = 'V';
			}
			$type = 'N';

		} elsif ($cur =~ /^(if|while|for)\b/o) {
			print "COND($1)\n" if ($dbg_values > 1);
			$av_pending = 'E';
			$type = 'N';

		} elsif ($cur =~/^(case)/o) {
			print "CASE($1)\n" if ($dbg_values > 1);
			$av_pend_colon = 'C';
			$type = 'N';

		} elsif ($cur =~/^(return|else|goto|typeof|__typeof__)\b/o) {
			print "KEYWORD($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~ /^(\()/o) {
			print "PAREN('$1')\n" if ($dbg_values > 1);
			push(@av_paren_type, $av_pending);
			$av_pending = '_';
			$type = 'N';

		} elsif ($cur =~ /^(\))/o) {
			my $new_type = pop(@av_paren_type);
			if ($new_type ne '_') {
				$type = $new_type;
				print "PAREN('$1') -> $type\n"
							if ($dbg_values > 1);
			} else {
				print "PAREN('$1')\n" if ($dbg_values > 1);
			}

		} elsif ($cur =~ /^($Ident)\s*\(/o) {
			print "FUNC($1)\n" if ($dbg_values > 1);
			$type = 'V';
			$av_pending = 'V';

		} elsif ($cur =~ /^($Ident\s*):(?:\s*\d+\s*(,|=|;))?/) {
			if (defined $2 && $type eq 'C' || $type eq 'T') {
				$av_pend_colon = 'B';
			} elsif ($type eq 'E') {
				$av_pend_colon = 'L';
			}
			print "IDENT_COLON($1,$type>$av_pend_colon)\n" if ($dbg_values > 1);
			$type = 'V';

		} elsif ($cur =~ /^($Ident|$Constant)/o) {
			print "IDENT($1)\n" if ($dbg_values > 1);
			$type = 'V';

		} elsif ($cur =~ /^($Assignment)/o) {
			print "ASSIGN($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~/^(;|{|})/) {
			print "END($1)\n" if ($dbg_values > 1);
			$type = 'E';
			$av_pend_colon = 'O';

		} elsif ($cur =~/^(,)/) {
			print "COMMA($1)\n" if ($dbg_values > 1);
			$type = 'C';

		} elsif ($cur =~ /^(\?)/o) {
			print "QUESTION($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~ /^(:)/o) {
			print "COLON($1,$av_pend_colon)\n" if ($dbg_values > 1);

			substr($var, length($res), 1, $av_pend_colon);
			if ($av_pend_colon eq 'C' || $av_pend_colon eq 'L') {
				$type = 'E';
			} else {
				$type = 'N';
			}
			$av_pend_colon = 'O';

		} elsif ($cur =~ /^(\[)/o) {
			print "CLOSE($1)\n" if ($dbg_values > 1);
			$type = 'N';

		} elsif ($cur =~ /^(-(?![->])|\+(?!\+)|\*|\&\&|\&)/o) {
			my $variant;

			print "OPV($1)\n" if ($dbg_values > 1);
			if ($type eq 'V') {
				$variant = 'B';
			} else {
				$variant = 'U';
			}

			substr($var, length($res), 1, $variant);
			$type = 'N';

		} elsif ($cur =~ /^($Operators)/o) {
			print "OP($1)\n" if ($dbg_values > 1);
			if ($1 ne '++' && $1 ne '--') {
				$type = 'N';
			}

		} elsif ($cur =~ /(^.)/o) {
			print "C($1)\n" if ($dbg_values > 1);
		}
		if (defined $1) {
			$cur = substr($cur, length($1));
			$res .= $type x length($1);
		}
	}

	return ($res, $var);
}

sub possible {
	my ($possible, $line) = @_;
	my $notPermitted = qr{(?:
		^(?:
			$Modifier|
			$Storage|
			$Type|
			DEFINE_\S+
		)$|
		^(?:
			goto|
			return|
			case|
			else|
			asm|__asm__|
			do|
			\#|
			\#\#|
		)(?:\s|$)|
		^(?:typedef|struct|enum)\b
	    )}x;
	warn "CHECK<$possible> ($line)\n" if ($dbg_possible > 2);
	if ($possible !~ $notPermitted) {
		# Check for modifiers.
		$possible =~ s/\s*$Storage\s*//g;
		$possible =~ s/\s*$Sparse\s*//g;
		if ($possible =~ /^\s*$/) {

		} elsif ($possible =~ /\s/) {
			$possible =~ s/\s*$Type\s*//g;
			for my $modifier (split(' ', $possible)) {
				if ($modifier !~ $notPermitted) {
					warn "MODIFIER: $modifier ($possible) ($line)\n" if ($dbg_possible);
					push(@modifierList, $modifier);
				}
			}

		} else {
			warn "POSSIBLE: $possible ($line)\n" if ($dbg_possible);
			push(@typeList, $possible);
		}
		build_types();
	} else {
		warn "NOTPOSS: $possible ($line)\n" if ($dbg_possible > 1);
	}
}

my $prefix = '';

sub show_type {
       return !defined $ignore_type{$_[0]};
}

sub report {
	if (!show_type($_[1]) ||
	    (defined $tst_only && $_[2] !~ /\Q$tst_only\E/)) {
		return 0;
	}
	my $line;
	if ($show_types) {
		$line = "$prefix$_[0]:$_[1]: $_[2]\n";
	} else {
		$line = "$prefix$_[0]: $_[2]\n";
	}
	$line = (split('\n', $line))[0] . "\n" if ($terse);

	push(our @report, $line);

	return 1;
}
sub report_dump {
	our @report;
}

sub ERROR {
	if (report("ERROR", $_[0], $_[1])) {
		our $clean = 0;
		our $cnt_error++;
	}
}
sub WARN {
	if (report("WARNING", $_[0], $_[1])) {
		our $clean = 0;
		our $cnt_warn++;
	}
}
sub CHK {
	if ($check && report("CHECK", $_[0], $_[1])) {
		our $clean = 0;
		our $cnt_chk++;
	}
}

sub check_absolute_file {
	my ($absolute, $herecurr) = @_;
	my $file = $absolute;

	##print "absolute<$absolute>\n";

	# See if any suffix of this path is a path within the tree.
	while ($file =~ s@^[^/]*/@@) {
		if (-f "$root/$file") {
			##print "file<$file>\n";
			last;
		}
	}
	if (! -f _)  {
		return 0;
	}

	# It is, so see if the prefix is acceptable.
	my $prefix = $absolute;
	substr($prefix, -length($file)) = '';

	##print "prefix<$prefix>\n";
	if ($prefix ne ".../") {
		WARN("USE_RELATIVE_PATH",
		     "use relative pathname instead of absolute in changelog text\n" . $herecurr);
	}
}

sub pos_last_openparen {
	my ($line) = @_;

	my $pos = 0;

	my $opens = $line =~ tr/\(/\(/;
	my $closes = $line =~ tr/\)/\)/;

	my $last_openparen = 0;

	if (($opens == 0) || ($closes >= $opens)) {
		return -1;
	}

	my $len = length($line);

	for ($pos = 0; $pos < $len; $pos++) {
		my $string = substr($line, $pos);
		if ($string =~ /^($FuncArg|$balanced_parens)/) {
			$pos += length($1) - 1;
		} elsif (substr($line, $pos, 1) eq '(') {
			$last_openparen = $pos;
		} elsif (index($string, '(') == -1) {
			last;
		}
	}

	return $last_openparen + 1;
}

sub process {
	my $filename = shift;

	my $linenr=0;
	my $prevline="";
	my $prevrawline="";
	my $stashline="";
	my $stashrawline="";

	my $length;
	my $indent;
	my $previndent=0;
	my $stashindent=0;

	our $clean = 1;
	my $signoff = 0;
	my $is_patch = 0;

	my $in_header_lines = 1;
	my $in_commit_log = 0;		#Scanning lines before patch

	our @report = ();
	our $cnt_lines = 0;
	our $cnt_error = 0;
	our $cnt_warn = 0;
	our $cnt_chk = 0;

	# Trace the real file/line as we go.
	my $realfile = '';
	my $realline = 0;
	my $realcnt = 0;
	my $here = '';
	my $in_comment = 0;
	my $comment_edge = 0;
	my $first_line = 0;
	my $p1_prefix = '';

	my $prev_values = 'E';

	# suppression flags
	my %suppress_ifbraces;
	my %suppress_whiletrailers;
	my %suppress_export;
	my $suppress_statement = 0;

	# Pre-scan the patch sanitizing the lines.
	sanitise_line_reset();
	my $line;
	foreach my $rawline (@rawlines) {
		$linenr++;
		$line = $rawline;

		if ($rawline=~/^\@\@ -\d+(?:,\d+)? \+(\d+)(,(\d+))? \@\@/) {
			$realline=$1-1;
			if (defined $2) {
				$realcnt=$3+1;
			} else {
				$realcnt=1+1;
			}
			$in_comment = 0;

			# Guestimate if this is a continuing comment.  Run
			# the context looking for a comment "edge".  If this
			# edge is a close comment then we must be in a comment
			# at context start.
			my $edge;
			my $cnt = $realcnt;
			for (my $ln = $linenr + 1; $cnt > 0; $ln++) {
				next if (defined $rawlines[$ln - 1] &&
					 $rawlines[$ln - 1] =~ /^-/);
				$cnt--;
				#print "RAW<$rawlines[$ln - 1]>\n";
				last if (!defined $rawlines[$ln - 1]);
				if ($rawlines[$ln - 1] =~ m@(/\*|\*/)@ &&
				    $rawlines[$ln - 1] !~ m@"[^"]*(?:/\*|\*/)[^"]*"@) {
					($edge) = $1;
					last;
				}
			}
			if (defined $edge && $edge eq '*/') {
				$in_comment = 1;
			}

			# Guestimate if this is a continuing comment.  If this
			# is the start of a diff block and this line starts
			# ' *' then it is very likely a comment.
			if (!defined $edge &&
			    $rawlines[$linenr] =~ m@^.\s*(?:\*\*+| \*)(?:\s|$)@)
			{
				$in_comment = 1;
			}

			##print "COMMENT:$in_comment edge<$edge> $rawline\n";
			sanitise_line_reset($in_comment);

		} elsif ($realcnt && $rawline =~ /^(?:\+| |$)/) {
			# Standardise the strings and chars within the input to
			# simplify matching -- only bother with positive lines.
			$line = sanitise_line($rawline);
		}
		push(@lines, $line);

		if ($realcnt > 1) {
			$realcnt-- if ($line =~ /^(?:\+| |$)/);
		} else {
			$realcnt = 0;
		}

		#print "==>$rawline\n";
		#print "-->$line\n";
	}

	$prefix = '';

	$realcnt = 0;
	$linenr = 0;
	foreach my $line (@lines) {
		$linenr++;

		my $rawline = $rawlines[$linenr - 1];

#extract the line range in the file after the patch is applied
		if ($line=~/^\@\@ -\d+(?:,\d+)? \+(\d+)(,(\d+))? \@\@/) {
			$is_patch = 1;
			$first_line = $linenr + 1;
			$realline=$1-1;
			if (defined $2) {
				$realcnt=$3+1;
			} else {
				$realcnt=1+1;
			}
			annotate_reset();
			$prev_values = 'E';

			%suppress_ifbraces = ();
			%suppress_whiletrailers = ();
			%suppress_export = ();
			$suppress_statement = 0;
			next;

# track the line number as we move through the hunk, note that
# new versions of GNU diff omit the leading space on completely
# blank context lines so we need to count that too.
		} elsif ($line =~ /^( |\+|$)/) {
			$realline++;
			$realcnt-- if ($realcnt != 0);

			# Measure the line length and indent.
			($length, $indent) = line_stats($rawline);

			# Track the previous line.
			($prevline, $stashline) = ($stashline, $line);
			($previndent, $stashindent) = ($stashindent, $indent);
			($prevrawline, $stashrawline) = ($stashrawline, $rawline);

			#warn "line<$line>\n";

		} elsif ($realcnt == 1) {
			$realcnt--;
		}

		my $hunk_line = ($realcnt != 0);

#make up the handle for any error we report on this line
		$prefix = "$filename:$realline: " if ($emacs && $file);
		$prefix = "$filename:$linenr: " if ($emacs && !$file);

		$here = "#$linenr: " if (!$file);
		$here = "#$realline: " if ($file);

		# extract the filename as it passes
		if ($line =~ /^diff --git.*?(\S+)$/) {
			$realfile = $1;
			$realfile =~ s@^([^/]*)/@@;
			$in_commit_log = 0;
		} elsif ($line =~ /^\+\+\+\s+(\S+)/) {
			$realfile = $1;
			$realfile =~ s@^([^/]*)/@@;
			$in_commit_log = 0;

			$p1_prefix = $1;
			if (!$file && $tree && $p1_prefix ne '' &&
			    -e "$root/$p1_prefix") {
				WARN("PATCH_PREFIX",
				     "patch prefix '$p1_prefix' exists, appears to be a -p0 patch\n");
			}

			if ($realfile =~ m@^include/asm/@) {
				ERROR("MODIFIED_INCLUDE_ASM",
				      "do not modify files in include/asm, change architecture specific files in include/asm-<architecture>\n" . "$here$rawline\n");
			}
			next;
		}

		$here .= "FILE: $realfile:$realline:" if ($realcnt != 0);

		my $hereline = "$here\n$rawline\n";
		my $herecurr = "$here\n$rawline\n";
		my $hereprev = "$here\n$prevrawline\n$rawline\n";

		$cnt_lines++ if ($realcnt != 0);

# Check for incorrect file permissions
		if ($line =~ /^new (file )?mode.*[7531]\d{0,2}$/) {
			my $permhere = $here . "FILE: $realfile\n";
			if ($realfile =~ /(Makefile|Kconfig|\.c|\.h|\.S|\.tmpl)$/) {
				ERROR("EXECUTE_PERMISSIONS",
				      "do not set execute permissions for source files\n" . $permhere);
			}
		}

# Check the patch for a signoff:
		if ($line =~ /^\s*signed-off-by:/i) {
			$signoff++;
			$in_commit_log = 0;
		}

# Check signature styles
		if (!$in_header_lines &&
		    $line =~ /^(\s*)($signature_tags)(\s*)(.*)/) {
			my $space_before = $1;
			my $sign_off = $2;
			my $space_after = $3;
			my $email = $4;
			my $ucfirst_sign_off = ucfirst(lc($sign_off));

			if (defined $space_before && $space_before ne "") {
				WARN("BAD_SIGN_OFF",
				     "Do not use whitespace before $ucfirst_sign_off\n" . $herecurr);
			}
			if ($sign_off =~ /-by:$/i && $sign_off ne $ucfirst_sign_off) {
				WARN("BAD_SIGN_OFF",
				     "'$ucfirst_sign_off' is the preferred signature form\n" . $herecurr);
			}
			if (!defined $space_after || $space_after ne " ") {
				WARN("BAD_SIGN_OFF",
				     "Use a single space after $ucfirst_sign_off\n" . $herecurr);
			}

			my ($email_name, $email_address, $comment) = parse_email($email);
			my $suggested_email = format_email(($email_name, $email_address));
			if ($suggested_email eq "") {
				ERROR("BAD_SIGN_OFF",
				      "Unrecognized email address: '$email'\n" . $herecurr);
			} else {
				my $dequoted = $suggested_email;
				$dequoted =~ s/^"//;
				$dequoted =~ s/" </ </;
				# Don't force email to have quotes
				# Allow just an angle bracketed address
				if ("$dequoted$comment" ne $email &&
				    "<$email_address>$comment" ne $email &&
				    "$suggested_email$comment" ne $email) {
					WARN("BAD_SIGN_OFF",
					     "email address '$email' might be better as '$suggested_email$comment'\n" . $herecurr);
				}
			}
		}

# Check for wrappage within a valid hunk of the file
		if ($realcnt != 0 && $line !~ m{^(?:\+|-| |\\ No newline|$)}) {
			ERROR("CORRUPTED_PATCH",
			      "patch seems to be corrupt (line wrapped?)\n" .
				$herecurr) if (!$emitted_corrupt++);
		}

# Check for absolute kernel paths.
		if ($tree) {
			while ($line =~ m{(?:^|\s)(/\S*)}g) {
				my $file = $1;

				if ($file =~ m{^(.*?)(?::\d+)+:?$} &&
				    check_absolute_file($1, $herecurr)) {
					#
				} else {
					check_absolute_file($file, $herecurr);
				}
			}
		}

# UTF-8 regex found at http://www.w3.org/International/questions/qa-forms-utf-8.en.php
		if (($realfile =~ /^$/ || $line =~ /^\+/) &&
		    $rawline !~ m/^$UTF8*$/) {
			my ($utf8_prefix) = ($rawline =~ /^($UTF8*)/);

			my $blank = copy_spacing($rawline);
			my $ptr = substr($blank, 0, length($utf8_prefix)) . "^";
			my $hereptr = "$hereline$ptr\n";

			CHK("INVALID_UTF8",
			    "Invalid UTF-8, patch and commit message should be encoded in UTF-8\n" . $hereptr);
		}

# Check if it's the start of a commit log
# (not a header line and we haven't seen the patch filename)
		if ($in_header_lines && $realfile =~ /^$/ &&
		    $rawline !~ /^(commit\b|from\b|[\w-]+:).+$/i) {
			$in_header_lines = 0;
			$in_commit_log = 1;
		}

# Still not yet in a patch, check for any UTF-8
		if ($in_commit_log && $realfile =~ /^$/ &&
		    $rawline =~ /$NON_ASCII_UTF8/) {
			CHK("UTF8_BEFORE_PATCH",
			    "8-bit UTF-8 used in possible commit log\n" . $herecurr);
		}

# ignore non-hunk lines and lines being removed
		next if (!$hunk_line || $line =~ /^-/);

#trailing whitespace
		if ($line =~ /^\+.*\015/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("DOS_LINE_ENDINGS",
			      "DOS line endings\n" . $herevet);

		} elsif ($rawline =~ /^\+.*\S\s+$/ || $rawline =~ /^\+\s+$/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("TRAILING_WHITESPACE",
			      "trailing whitespace\n" . $herevet);
			$rpt_cleaners = 1;
		}

# check for Kconfig help text having a real description
# Only applies when adding the entry originally, after that we do not have
# sufficient context to determine whether it is indeed long enough.
		if ($realfile =~ /Kconfig/ &&
		    $line =~ /.\s*config\s+/) {
			my $length = 0;
			my $cnt = $realcnt;
			my $ln = $linenr + 1;
			my $f;
			my $is_start = 0;
			my $is_end = 0;
			for (; $cnt > 0 && defined $lines[$ln - 1]; $ln++) {
				$f = $lines[$ln - 1];
				$cnt-- if ($lines[$ln - 1] !~ /^-/);
				$is_end = $lines[$ln - 1] =~ /^\+/;

				next if ($f =~ /^-/);

				if ($lines[$ln - 1] =~ /.\s*(?:bool|tristate)\s*\"/) {
					$is_start = 1;
				} elsif ($lines[$ln - 1] =~ /.\s*(?:---)?help(?:---)?$/) {
					$length = -1;
				}

				$f =~ s/^.//;
				$f =~ s/#.*//;
				$f =~ s/^\s+//;
				next if ($f =~ /^$/);
				if ($f =~ /^\s*config\s/) {
					$is_end = 1;
					last;
				}
				$length++;
			}
			WARN("CONFIG_DESCRIPTION",
			     "please write a paragraph that describes the config symbol fully\n" . $herecurr) if ($is_start && $is_end && $length < 4);
			#print "is_start<$is_start> is_end<$is_end> length<$length>\n";
		}

		if (($realfile =~ /Makefile.*/ || $realfile =~ /Kbuild.*/) &&
		    ($line =~ /\+(EXTRA_[A-Z]+FLAGS).*/)) {
			my $flag = $1;
			my $replacement = {
				'EXTRA_AFLAGS' =>   'asflags-y',
				'EXTRA_CFLAGS' =>   'ccflags-y',
				'EXTRA_CPPFLAGS' => 'cppflags-y',
				'EXTRA_LDFLAGS' =>  'ldflags-y',
			};

			WARN("DEPRECATED_VARIABLE",
			     "Use of $flag is deprecated, please use \`$replacement->{$flag} instead.\n" . $herecurr) if ($replacement->{$flag});
		}

# check we are in a valid source file if not then ignore this hunk
		next if ($realfile !~ /\.(h|c|s|S|pl|sh)$/);

#80 column limit
		if ($line =~ /^\+/ && $prevrawline !~ /\/\*\*/ &&
		    $rawline !~ /^.\s*\*\s*\@$Ident\s/ &&
		    !($line =~ /^\+\s*$logFunctions\s*\(\s*(?:(KERN_\S+\s*|[^"]*))?"[X\t]*"\s*(?:|,|\)\s*;)\s*$/ ||
		    $line =~ /^\+\s*"[^"]*"\s*(?:\s*|,|\)\s*;)\s*$/) &&
		    $length > 80)
		{
			WARN("LONG_LINE",
			     "line over 80 characters\n" . $herecurr);
		}

# Check for user-visible strings broken across lines, which breaks the ability
# to grep for the string.  Limited to strings used as parameters (those
# following an open parenthesis), which almost completely eliminates false
# positives, as well as warning only once per parameter rather than once per
# line of the string.  Make an exception when the previous string ends in a
# newline (multiple lines in one string constant) or \n\t (common in inline
# assembly to indent the instruction on the following line).
		if ($line =~ /^\+\s*"/ &&
		    $prevline =~ /"\s*$/ &&
		    $prevline =~ /\(/ &&
		    $prevrawline !~ /\\n(?:\\t)*"\s*$/) {
			WARN("SPLIT_STRING",
			     "quoted string split across lines\n" . $hereprev);
		}

# check for spaces before a quoted newline
		if ($rawline =~ /^.*\".*\s\\n/) {
			WARN("QUOTED_WHITESPACE_BEFORE_NEWLINE",
			     "unnecessary whitespace before a quoted newline\n" . $herecurr);
		}

# check for adding lines without a newline.
		if ($line =~ /^\+/ && defined $lines[$linenr] && $lines[$linenr] =~ /^\\ No newline at end of file/) {
			WARN("MISSING_EOF_NEWLINE",
			     "adding a line without newline at end of file\n" . $herecurr);
		}

# Blackfin: use hi/lo macros
		if ($realfile =~ m@arch/blackfin/.*\.S$@) {
			if ($line =~ /\.[lL][[:space:]]*=.*&[[:space:]]*0x[fF][fF][fF][fF]/) {
				my $herevet = "$here\n" . cat_vet($line) . "\n";
				ERROR("LO_MACRO",
				      "use the LO() macro, not (... & 0xFFFF)\n" . $herevet);
			}
			if ($line =~ /\.[hH][[:space:]]*=.*>>[[:space:]]*16/) {
				my $herevet = "$here\n" . cat_vet($line) . "\n";
				ERROR("HI_MACRO",
				      "use the HI() macro, not (... >> 16)\n" . $herevet);
			}
		}

# check we are in a valid source file C or perl if not then ignore this hunk
		next if ($realfile !~ /\.(h|c|pl)$/);

# at the beginning of a line any tabs must come first and anything
# more than 8 must use tabs.
		if ($rawline =~ /^\+\s* \t\s*\S/ ||
		    $rawline =~ /^\+\s*        \s*/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			ERROR("CODE_INDENT",
			      "code indent should use tabs where possible\n" . $herevet);
			$rpt_cleaners = 1;
		}

# check for space before tabs.
		if ($rawline =~ /^\+/ && $rawline =~ / \t/) {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			WARN("SPACE_BEFORE_TAB",
			     "please, no space before tabs\n" . $herevet);
		}

# check for && or || at the start of a line
		if ($rawline =~ /^\+\s*(&&|\|\|)/) {
			CHK("LOGICAL_CONTINUATIONS",
			    "Logical continuations should be on the previous line\n" . $hereprev);
		}

# check multi-line statement indentation matches previous line
		if ($^V && $^V ge 5.10.0 &&
		    $prevline =~ /^\+(\t*)(if \(|$Ident\().*(\&\&|\|\||,)\s*$/) {
			$prevline =~ /^\+(\t*)(.*)$/;
			my $oldindent = $1;
			my $rest = $2;

			my $pos = pos_last_openparen($rest);
			if ($pos >= 0) {
				$line =~ /^\+([ \t]*)/;
				my $newindent = $1;

				my $goodtabindent = $oldindent .
					"\t" x ($pos / 8) .
					" "  x ($pos % 8);
				my $goodspaceindent = $oldindent . " "  x $pos;

				if ($newindent ne $goodtabindent &&
				    $newindent ne $goodspaceindent) {
					CHK("PARENTHESIS_ALIGNMENT",
					    "Alignment should match open parenthesis\n" . $hereprev);
				}
			}
		}

		if ($line =~ /^\+.*\*[ \t]*\)[ \t]+/) {
			CHK("SPACING",
			    "No space is necessary after a cast\n" . $hereprev);
		}

		if ($rawline =~ /^\+[ \t]*\/\*[ \t]*$/ &&
		    $prevrawline =~ /^\+[ \t]*$/) {
			CHK("BLOCK_COMMENT_STYLE",
			    "Don't begin block comments with only a /* line, use /* comment...\n" . $hereprev);
		}

# check for spaces at the beginning of a line.
# Exceptions:
#  1) within comments
#  2) indented preprocessor commands
#  3) hanging labels
		if ($rawline =~ /^\+ / && $line !~ /\+ *(?:$;|#|$Ident:)/)  {
			my $herevet = "$here\n" . cat_vet($rawline) . "\n";
			WARN("LEADING_SPACE",
			     "please, no spaces at the start of a line\n" . $herevet);
		}

# check we are in a valid C source file if not then ignore this hunk
		next if ($realfile !~ /\.(h|c)$/);

# check for RCS/CVS revision markers
		if ($rawline =~ /^\+.*\$(Revision|Log|Id)(?:\$|)/) {
			WARN("CVS_KEYWORD",
			     "CVS style keyword markers, these will _not_ be updated\n". $herecurr);
		}

# Blackfin: don't use __builtin_bfin_[cs]sync
		if ($line =~ /__builtin_bfin_csync/) {
			my $herevet = "$here\n" . cat_vet($line) . "\n";
			ERROR("CSYNC",
			      "use the CSYNC() macro in asm/blackfin.h\n" . $herevet);
		}
		if ($line =~ /__builtin_bfin_ssync/) {
			my $herevet = "$here\n" . cat_vet($line) . "\n";
			ERROR("SSYNC",
			      "use the SSYNC() macro in asm/blackfin.h\n" . $herevet);
		}

# Check for potential 'bare' types
		my ($stat, $cond, $line_nr_next, $remain_next, $off_next,
		    $realline_next);
#print "LINE<$line>\n";
		if ($linenr >= $suppress_statement &&
		    $realcnt && $line =~ /.\s*\S/) {
			($stat, $cond, $line_nr_next, $remain_next, $off_next) =
				ctx_statement_block($linenr, $realcnt, 0);
			$stat =~ s/\n./\n /g;
			$cond =~ s/\n./\n /g;

#print "linenr<$linenr> <$stat>\n";
			# If this statement has no statement boundaries within
			# it there is no point in retrying a statement scan
			# until we hit end of it.
			my $frag = $stat; $frag =~ s/;+\s*$//;
			if ($frag !~ /(?:{|;)/) {
#print "skip<$line_nr_next>\n";
				$suppress_statement = $line_nr_next;
			}

			# Find the real next line.
			$realline_next = $line_nr_next;
			if (defined $realline_next &&
			    (!defined $lines[$realline_next - 1] ||
			     substr($lines[$realline_next - 1], $off_next) =~ /^\s*$/)) {
				$realline_next++;
			}

			my $s = $stat;
			$s =~ s/{.*$//s;

			# Ignore goto labels.
			if ($s =~ /$Ident:\*$/s) {

			# Ignore functions being called
			} elsif ($s =~ /^.\s*$Ident\s*\(/s) {

			} elsif ($s =~ /^.\s*else\b/s) {

			# declarations always start with types
			} elsif ($prev_values eq 'E' && $s =~ /^.\s*(?:$Storage\s+)?(?:$Inline\s+)?(?:const\s+)?((?:\s*$Ident)+?)\b(?:\s+$Sparse)?\s*\**\s*(?:$Ident|\(\*[^\)]*\))(?:\s*$Modifier)?\s*(?:;|=|,|\()/s) {
				my $type = $1;
				$type =~ s/\s+/ /g;
				possible($type, "A:" . $s);

			# definitions in global scope can only start with types
			} elsif ($s =~ /^.(?:$Storage\s+)?(?:$Inline\s+)?(?:const\s+)?($Ident)\b\s*(?!:)/s) {
				possible($1, "B:" . $s);
			}

			# any (foo ... *) is a pointer cast, and foo is a type
			while ($s =~ /\(($Ident)(?:\s+$Sparse)*[\s\*]+\s*\)/sg) {
				possible($1, "C:" . $s);
			}

			# Check for any sort of function declaration.
			# int foo(something bar, other baz);
			# void (*store_gdt)(x86_descr_ptr *);
			if ($prev_values eq 'E' && $s =~ /^(.(?:typedef\s*)?(?:(?:$Storage|$Inline)\s*)*\s*$Type\s*(?:\b$Ident|\(\*\s*$Ident\))\s*)\(/s) {
				my ($name_len) = length($1);

				my $ctx = $s;
				substr($ctx, 0, $name_len + 1, '');
				$ctx =~ s/\)[^\)]*$//;

				for my $arg (split(/\s*,\s*/, $ctx)) {
					if ($arg =~ /^(?:const\s+)?($Ident)(?:\s+$Sparse)*\s*\**\s*(:?\b$Ident)?$/s || $arg =~ /^($Ident)$/s) {

						possible($1, "D:" . $s);
					}
				}
			}

		}

#
# Checks which may be anchored in the context.
#

# Check for switch () and associated case and default
# statements should be at the same indent.
		if ($line=~/\bswitch\s*\(.*\)/) {
			my $err = '';
			my $sep = '';
			my @ctx = ctx_block_outer($linenr, $realcnt);
			shift(@ctx);
			for my $ctx (@ctx) {
				my ($clen, $cindent) = line_stats($ctx);
				if ($ctx =~ /^\+\s*(case\s+|default:)/ &&
							$indent != $cindent) {
					$err .= "$sep$ctx\n";
					$sep = '';
				} else {
					$sep = "[...]\n";
				}
			}
			if ($err ne '') {
				ERROR("SWITCH_CASE_INDENT_LEVEL",
				      "switch and case should be at the same indent\n$hereline$err");
			}
		}

# if/while/etc brace do not go on next line, unless defining a do while loop,
# or if that brace on the next line is for something else
		if ($line =~ /(.*)\b((?:if|while|for|switch)\s*\(|do\b|else\b)/ && $line !~ /^.\s*\#/) {
			my $pre_ctx = "$1$2";

			my ($level, @ctx) = ctx_statement_level($linenr, $realcnt, 0);

			if ($line =~ /^\+\t{6,}/) {
				WARN("DEEP_INDENTATION",
				     "Too many leading tabs - consider code refactoring\n" . $herecurr);
			}

			my $ctx_cnt = $realcnt - $#ctx - 1;
			my $ctx = join("\n", @ctx);

			my $ctx_ln = $linenr;
			my $ctx_skip = $realcnt;

			while ($ctx_skip > $ctx_cnt || ($ctx_skip == $ctx_cnt &&
					defined $lines[$ctx_ln - 1] &&
					$lines[$ctx_ln - 1] =~ /^-/)) {
				##print "SKIP<$ctx_skip> CNT<$ctx_cnt>\n";
				$ctx_skip-- if (!defined $lines[$ctx_ln - 1] || $lines[$ctx_ln - 1] !~ /^-/);
				$ctx_ln++;
			}

			#print "realcnt<$realcnt> ctx_cnt<$ctx_cnt>\n";
			#print "pre<$pre_ctx>\nline<$line>\nctx<$ctx>\nnext<$lines[$ctx_ln - 1]>\n";

			if ($ctx !~ /{\s*/ && defined($lines[$ctx_ln -1]) && $lines[$ctx_ln - 1] =~ /^\+\s*{/) {
				ERROR("OPEN_BRACE",
				      "that open brace { should be on the previous line\n" .
					"$here\n$ctx\n$rawlines[$ctx_ln - 1]\n");
			}
			if ($level == 0 && $pre_ctx !~ /}\s*while\s*\($/ &&
			    $ctx =~ /\)\s*\;\s*$/ &&
			    defined $lines[$ctx_ln - 1])
			{
				my ($nlength, $nindent) = line_stats($lines[$ctx_ln - 1]);
				if ($nindent > $indent) {
					WARN("TRAILING_SEMICOLON",
					     "trailing semicolon indicates no statements, indent implies otherwise\n" .
						"$here\n$ctx\n$rawlines[$ctx_ln - 1]\n");
				}
			}
		}

# Check relative indent for conditionals and blocks.
		if ($line =~ /\b(?:(?:if|while|for)\s*\(|do\b)/ && $line !~ /^.\s*#/ && $line !~ /\}\s*while\s*/) {
			($stat, $cond, $line_nr_next, $remain_next, $off_next) =
				ctx_statement_block($linenr, $realcnt, 0)
					if (!defined $stat);
			my ($s, $c) = ($stat, $cond);

			substr($s, 0, length($c), '');

			# Make sure we remove the line prefixes as we have
			# none on the first line, and are going to readd them
			# where necessary.
			$s =~ s/\n./\n/gs;

			# Find out how long the conditional actually is.
			my @newlines = ($c =~ /\n/gs);
			my $cond_lines = 1 + $#newlines;

			# We want to check the first line inside the block
			# starting at the end of the conditional, so remove:
			#  1) any blank line termination
			#  2) any opening brace { on end of the line
			#  3) any do (...) {
			my $continuation = 0;
			my $check = 0;
			$s =~ s/^.*\bdo\b//;
			$s =~ s/^\s*{//;
			if ($s =~ s/^\s*\\//) {
				$continuation = 1;
			}
			if ($s =~ s/^\s*?\n//) {
				$check = 1;
				$cond_lines++;
			}

			# Also ignore a loop construct at the end of a
			# preprocessor statement.
			if (($prevline =~ /^.\s*#\s*define\s/ ||
			    $prevline =~ /\\\s*$/) && $continuation == 0) {
				$check = 0;
			}

			my $cond_ptr = -1;
			$continuation = 0;
			while ($cond_ptr != $cond_lines) {
				$cond_ptr = $cond_lines;

				# If we see an #else/#elif then the code
				# is not linear.
				if ($s =~ /^\s*\#\s*(?:else|elif)/) {
					$check = 0;
				}

				# Ignore:
				#  1) blank lines, they should be at 0,
				#  2) preprocessor lines, and
				#  3) labels.
				if ($continuation ||
				    $s =~ /^\s*?\n/ ||
				    $s =~ /^\s*#\s*?/ ||
				    $s =~ /^\s*$Ident\s*:/) {
					$continuation = ($s =~ /^.*?\\\n/) ? 1 : 0;
					if ($s =~ s/^.*?\n//) {
						$cond_lines++;
					}
				}
			}

			my (undef, $sindent) = line_stats("+" . $s);
			my $stat_real = raw_line($linenr, $cond_lines);

			# Check if either of these lines are modified, else
			# this is not this patch's fault.
			if (!defined($stat_real) ||
			    $stat !~ /^\+/ && $stat_real !~ /^\+/) {
				$check = 0;
			}
			if (defined($stat_real) && $cond_lines > 1) {
				$stat_real = "[...]\n$stat_real";
			}

			#print "line<$line> prevline<$prevline> indent<$indent> sindent<$sindent> check<$check> continuation<$continuation> s<$s> cond_lines<$cond_lines> stat_real<$stat_real> stat<$stat>\n";

			if ($check && (($sindent % 8) != 0 ||
			    ($sindent <= $indent && $s ne ''))) {
				WARN("SUSPECT_CODE_INDENT",
				     "suspect code indent for conditional statements ($indent, $sindent)\n" . $herecurr . "$stat_real\n");
			}
		}

		# Track the 'values' across context and added lines.
		my $opline = $line; $opline =~ s/^./ /;
		my ($curr_values, $curr_vars) =
				annotate_values($opline . "\n", $prev_values);
		$curr_values = $prev_values . $curr_values;
		if ($dbg_values) {
			my $outline = $opline; $outline =~ s/\t/ /g;
			print "$linenr > .$outline\n";
			print "$linenr > $curr_values\n";
			print "$linenr >  $curr_vars\n";
		}
		$prev_values = substr($curr_values, -1);

#ignore lines not being added
		if ($line=~/^[^\+]/) {next;}

# TEST: allow direct testing of the type matcher.
		if ($dbg_type) {
			if ($line =~ /^.\s*$Declare\s*$/) {
				ERROR("TEST_TYPE",
				      "TEST: is type\n" . $herecurr);
			} elsif ($dbg_type > 1 && $line =~ /^.+($Declare)/) {
				ERROR("TEST_NOT_TYPE",
				      "TEST: is not type ($1 is)\n". $herecurr);
			}
			next;
		}
# TEST: allow direct testing of the attribute matcher.
		if ($dbg_attr) {
			if ($line =~ /^.\s*$Modifier\s*$/) {
				ERROR("TEST_ATTR",
				      "TEST: is attr\n" . $herecurr);
			} elsif ($dbg_attr > 1 && $line =~ /^.+($Modifier)/) {
				ERROR("TEST_NOT_ATTR",
				      "TEST: is not attr ($1 is)\n". $herecurr);
			}
			next;
		}

# check for initialisation to aggregates open brace on the next line
		if ($line =~ /^.\s*{/ &&
		    $prevline =~ /(?:^|[^=])=\s*$/) {
			ERROR("OPEN_BRACE",
			      "that open brace { should be on the previous line\n" . $hereprev);
		}

#
# Checks which are anchored on the added line.
#

# check for malformed paths in #include statements (uses RAW line)
		if ($rawline =~ m{^.\s*\#\s*include\s+[<"](.*)[">]}) {
			my $path = $1;
			if ($path =~ m{//}) {
				ERROR("MALFORMED_INCLUDE",
				      "malformed #include filename\n" .
					$herecurr);
			}
		}

# no C99 // comments
		if ($line =~ m{//}) {
			ERROR("C99_COMMENTS",
			      "do not use C99 // comments\n" . $herecurr);
		}
		# Remove C99 comments.
		$line =~ s@//.*@@;
		$opline =~ s@//.*@@;

# EXPORT_SYMBOL should immediately follow the thing it is exporting, consider
# the whole statement.
#print "APW <$lines[$realline_next - 1]>\n";
		if (defined $realline_next &&
		    exists $lines[$realline_next - 1] &&
		    !defined $suppress_export{$realline_next} &&
		    ($lines[$realline_next - 1] =~ /EXPORT_SYMBOL.*\((.*)\)/ ||
		     $lines[$realline_next - 1] =~ /EXPORT_UNUSED_SYMBOL.*\((.*)\)/)) {
			# Handle definitions which produce identifiers with
			# a prefix:
			#   XXX(foo);
			#   EXPORT_SYMBOL(something_foo);
			my $name = $1;
			if ($stat =~ /^(?:.\s*}\s*\n)?.([A-Z_]+)\s*\(\s*($Ident)/ &&
			    $name =~ /^${Ident}_$2/) {
#print "FOO C name<$name>\n";
				$suppress_export{$realline_next} = 1;

			} elsif ($stat !~ /(?:
				\n.}\s*$|
				^.DEFINE_$Ident\(\Q$name\E\)|
				^.DECLARE_$Ident\(\Q$name\E\)|
				^.LIST_HEAD\(\Q$name\E\)|
				^.(?:$Storage\s+)?$Type\s*\(\s*\*\s*\Q$name\E\s*\)\s*\(|
				\b\Q$name\E(?:\s+$Attribute)*\s*(?:;|=|\[|\()
			    )/x) {
#print "FOO A<$lines[$realline_next - 1]> stat<$stat> name<$name>\n";
				$suppress_export{$realline_next} = 2;
			} else {
				$suppress_export{$realline_next} = 1;
			}
		}
		if (!defined $suppress_export{$linenr} &&
		    $prevline =~ /^.\s*$/ &&
		    ($line =~ /EXPORT_SYMBOL.*\((.*)\)/ ||
		     $line =~ /EXPORT_UNUSED_SYMBOL.*\((.*)\)/)) {
#print "FOO B <$lines[$linenr - 1]>\n";
			$suppress_export{$linenr} = 2;
		}
		if (defined $suppress_export{$linenr} &&
		    $suppress_export{$linenr} == 2) {
			WARN("EXPORT_SYMBOL",
			     "EXPORT_SYMBOL(foo); should immediately follow its function/variable\n" . $herecurr);
		}

# check for global initialisers.
		if ($line =~ /^.$Type\s*$Ident\s*(?:\s+$Modifier)*\s*=\s*(0|NULL|false)\s*;/) {
			ERROR("GLOBAL_INITIALISERS",
			      "do not initialise globals to 0 or NULL\n" .
				$herecurr);
		}
# check for static initialisers.
		if ($line =~ /\bstatic\s.*=\s*(0|NULL|false)\s*;/) {
			ERROR("INITIALISED_STATIC",
			      "do not initialise statics to 0 or NULL\n" .
				$herecurr);
		}

# check for static const char * arrays.
		if ($line =~ /\bstatic\s+const\s+char\s*\*\s*(\w+)\s*\[\s*\]\s*=\s*/) {
			WARN("STATIC_CONST_CHAR_ARRAY",
			     "static const char * array should probably be static const char * const\n" .
				$herecurr);
               }

# check for static char foo[] = "bar" declarations.
		if ($line =~ /\bstatic\s+char\s+(\w+)\s*\[\s*\]\s*=\s*"/) {
			WARN("STATIC_CONST_CHAR_ARRAY",
			     "static char array declaration should probably be static const char\n" .
				$herecurr);
               }

# check for declarations of struct pci_device_id
		if ($line =~ /\bstruct\s+pci_device_id\s+\w+\s*\[\s*\]\s*\=\s*\{/) {
			WARN("DEFINE_PCI_DEVICE_TABLE",
			     "Use DEFINE_PCI_DEVICE_TABLE for struct pci_device_id\n" . $herecurr);
		}

# check for new typedefs, only function parameters and sparse annotations
# make sense.
		if ($line =~ /\btypedef\s/ &&
		    $line !~ /\btypedef\s+$Type\s*\(\s*\*?$Ident\s*\)\s*\(/ &&
		    $line !~ /\btypedef\s+$Type\s+$Ident\s*\(/ &&
		    $line !~ /\b$typeTypedefs\b/ &&
		    $line !~ /\b__bitwise(?:__|)\b/) {
			WARN("NEW_TYPEDEFS",
			     "do not add new typedefs\n" . $herecurr);
		}

# * goes on variable not on type
		# (char*[ const])
		while ($line =~ m{(\($NonptrType(\s*(?:$Modifier\b\s*|\*\s*)+)\))}g) {
			#print "AA<$1>\n";
			my ($from, $to) = ($2, $2);

			# Should start with a space.
			$to =~ s/^(\S)/ $1/;
			# Should not end with a space.
			$to =~ s/\s+$//;
			# '*'s should not have spaces between.
			while ($to =~ s/\*\s+\*/\*\*/) {
			}

			#print "from<$from> to<$to>\n";
			if ($from ne $to) {
				ERROR("POINTER_LOCATION",
				      "\"(foo$from)\" should be \"(foo$to)\"\n" .  $herecurr);
			}
		}
		while ($line =~ m{(\b$NonptrType(\s*(?:$Modifier\b\s*|\*\s*)+)($Ident))}g) {
			#print "BB<$1>\n";
			my ($from, $to, $ident) = ($2, $2, $3);

			# Should start with a space.
			$to =~ s/^(\S)/ $1/;
			# Should not end with a space.
			$to =~ s/\s+$//;
			# '*'s should not have spaces between.
			while ($to =~ s/\*\s+\*/\*\*/) {
			}
			# Modifiers should have spaces.
			$to =~ s/(\b$Modifier$)/$1 /;

			#print "from<$from> to<$to> ident<$ident>\n";
			if ($from ne $to && $ident !~ /^$Modifier$/) {
				ERROR("POINTER_LOCATION",
				      "\"foo${from}bar\" should be \"foo${to}bar\"\n" .  $herecurr);
			}
		}

# # no BUG() or BUG_ON()
#		if ($line =~ /\b(BUG|BUG_ON)\b/) {
#			print "Try to use WARN_ON & Recovery code rather than BUG() or BUG_ON()\n";
#			print "$herecurr";
#			$clean = 0;
#		}

		if ($line =~ /\bLINUX_VERSION_CODE\b/) {
			WARN("LINUX_VERSION_CODE",
			     "LINUX_VERSION_CODE should be avoided, code should be for the version to which it is merged\n" . $herecurr);
		}

# check for uses of printk_ratelimit
		if ($line =~ /\bprintk_ratelimit\s*\(/) {
			WARN("PRINTK_RATELIMITED",
"Prefer printk_ratelimited or pr_<level>_ratelimited to printk_ratelimit\n" . $herecurr);
		}

# printk should use KERN_* levels.  Note that follow on printk's on the
# same line do not need a level, so we use the current block context
# to try and find and validate the current printk.  In summary the current
# printk includes all preceding printk's which have no newline on the end.
# we assume the first bad printk is the one to report.
		if ($line =~ /\bprintk\((?!KERN_)\s*"/) {
			my $ok = 0;
			for (my $ln = $linenr - 1; $ln >= $first_line; $ln--) {
				#print "CHECK<$lines[$ln - 1]\n";
				# we have a preceding printk if it ends
				# with "\n" ignore it, else it is to blame
				if ($lines[$ln - 1] =~ m{\bprintk\(}) {
					if ($rawlines[$ln - 1] !~ m{\\n"}) {
						$ok = 1;
					}
					last;
				}
			}
			if ($ok == 0) {
				WARN("PRINTK_WITHOUT_KERN_LEVEL",
				     "printk() should include KERN_ facility level\n" . $herecurr);
			}
		}

# function brace can't be on same line, except for #defines of do while,
# or if closed on same line
		if (($line=~/$Type\s*$Ident\(.*\).*\s\{/) and
		    !($line=~/\#\s*define.*do\s\{/) and !($line=~/}/)) {
			ERROR("OPEN_BRACE",
			      "open brace '{' following function declarations go on the next line\n" . $herecurr);
		}

# open braces for enum, union and struct go on the same line.
		if ($line =~ /^.\s*{/ &&
		    $prevline =~ /^.\s*(?:typedef\s+)?(enum|union|struct)(?:\s+$Ident)?\s*$/) {
			ERROR("OPEN_BRACE",
			      "open brace '{' following $1 go on the same line\n" . $hereprev);
		}

# missing space after union, struct or enum definition
		if ($line =~ /^.\s*(?:typedef\s+)?(enum|union|struct)(?:\s+$Ident)?(?:\s+$Ident)?[=\{]/) {
		    WARN("SPACING",
			 "missing space after $1 definition\n" . $herecurr);
		}

# check for spacing round square brackets; allowed:
#  1. with a type on the left -- int [] a;
#  2. at the beginning of a line for slice initialisers -- [0...10] = 5,
#  3. inside a curly brace -- = { [0...10] = 5 }
		while ($line =~ /(.*?\s)\[/g) {
			my ($where, $prefix) = ($-[1], $1);
			if ($prefix !~ /$Type\s+$/ &&
			    ($where != 0 || $prefix !~ /^.\s+$/) &&
			    $prefix !~ /[{,]\s+$/) {
				ERROR("BRACKET_SPACE",
				      "space prohibited before open square bracket '['\n" . $herecurr);
			}
		}

# check for spaces between functions and their parentheses.
		while ($line =~ /($Ident)\s+\(/g) {
			my $name = $1;
			my $ctx_before = substr($line, 0, $-[1]);
			my $ctx = "$ctx_before$name";

			# Ignore those directives where spaces _are_ permitted.
			if ($name =~ /^(?:
				if|for|while|switch|return|case|
				volatile|__volatile__|
				__attribute__|format|__extension__|
				asm|__asm__)$/x)
			{

			# cpp #define statements have non-optional spaces, ie
			# if there is a space between the name and the open
			# parenthesis it is simply not a parameter group.
			} elsif ($ctx_before =~ /^.\s*\#\s*define\s*$/) {

			# cpp #elif statement condition may start with a (
			} elsif ($ctx =~ /^.\s*\#\s*elif\s*$/) {

			# If this whole things ends with a type its most
			# likely a typedef for a function.
			} elsif ($ctx =~ /$Type$/) {

			} else {
				WARN("SPACING",
				     "space prohibited between function name and open parenthesis '('\n" . $herecurr);
			}
		}
# Check operator spacing.
		if (!($line=~/\#\s*include/)) {
			my $ops = qr{
				<<=|>>=|<=|>=|==|!=|
				\+=|-=|\*=|\/=|%=|\^=|\|=|&=|
				=>|->|<<|>>|<|>|=|!|~|
				&&|\|\||,|\^|\+\+|--|&|\||\+|-|\*|\/|%|
				\?|:
			}x;
			my @elements = split(/($ops|;)/, $opline);
			my $off = 0;

			my $blank = copy_spacing($opline);

			for (my $n = 0; $n < $#elements; $n += 2) {
				$off += length($elements[$n]);

				# Pick up the preceding and succeeding characters.
				my $ca = substr($opline, 0, $off);
				my $cc = '';
				if (length($opline) >= ($off + length($elements[$n + 1]))) {
					$cc = substr($opline, $off + length($elements[$n + 1]));
				}
				my $cb = "$ca$;$cc";

				my $a = '';
				$a = 'V' if ($elements[$n] ne '');
				$a = 'W' if ($elements[$n] =~ /\s$/);
				$a = 'C' if ($elements[$n] =~ /$;$/);
				$a = 'B' if ($elements[$n] =~ /(\[|\()$/);
				$a = 'O' if ($elements[$n] eq '');
				$a = 'E' if ($ca =~ /^\s*$/);

				my $op = $elements[$n + 1];

				my $c = '';
				if (defined $elements[$n + 2]) {
					$c = 'V' if ($elements[$n + 2] ne '');
					$c = 'W' if ($elements[$n + 2] =~ /^\s/);
					$c = 'C' if ($elements[$n + 2] =~ /^$;/);
					$c = 'B' if ($elements[$n + 2] =~ /^(\)|\]|;)/);
					$c = 'O' if ($elements[$n + 2] eq '');
					$c = 'E' if ($elements[$n + 2] =~ /^\s*\\$/);
				} else {
					$c = 'E';
				}

				my $ctx = "${a}x${c}";

				my $at = "(ctx:$ctx)";

				my $ptr = substr($blank, 0, $off) . "^";
				my $hereptr = "$hereline$ptr\n";

				# Pull out the value of this operator.
				my $op_type = substr($curr_values, $off + 1, 1);

				# Get the full operator variant.
				my $opv = $op . substr($curr_vars, $off, 1);

				# Ignore operators passed as parameters.
				if ($op_type ne 'V' &&
				    $ca =~ /\s$/ && $cc =~ /^\s*,/) {

#				# Ignore comments
#				} elsif ($op =~ /^$;+$/) {

				# ; should have either the end of line or a space or \ after it
				} elsif ($op eq ';') {
					if ($ctx !~ /.x[WEBC]/ &&
					    $cc !~ /^\\/ && $cc !~ /^;/) {
						ERROR("SPACING",
						      "space required after that '$op' $at\n" . $hereptr);
					}

				# // is a comment
				} elsif ($op eq '//') {

				# No spaces for:
				#   ->
				#   :   when part of a bitfield
				} elsif ($op eq '->' || $opv eq ':B') {
					if ($ctx =~ /Wx.|.xW/) {
						ERROR("SPACING",
						      "spaces prohibited around that '$op' $at\n" . $hereptr);
					}

				# , must have a space on the right.
				} elsif ($op eq ',') {
					if ($ctx !~ /.x[WEC]/ && $cc !~ /^}/) {
						ERROR("SPACING",
						      "space required after that '$op' $at\n" . $hereptr);
					}

				# '*' as part of a type definition -- reported already.
				} elsif ($opv eq '*_') {
					#warn "'*' is part of type\n";

				# unary operators should have a space before and
				# none after.  May be left adjacent to another
				# unary operator, or a cast
				} elsif ($op eq '!' || $op eq '~' ||
					 $opv eq '*U' || $opv eq '-U' ||
					 $opv eq '&U' || $opv eq '&&U') {
					if ($ctx !~ /[WEBC]x./ && $ca !~ /(?:\)|!|~|\*|-|\&|\||\+\+|\-\-|\{)$/) {
						ERROR("SPACING",
						      "space required before that '$op' $at\n" . $hereptr);
					}
					if ($op eq '*' && $cc =~/\s*$Modifier\b/) {
						# A unary '*' may be const

					} elsif ($ctx =~ /.xW/) {
						ERROR("SPACING",
						      "space prohibited after that '$op' $at\n" . $hereptr);
					}

				# unary ++ and unary -- are allowed no space on one side.
				} elsif ($op eq '++' or $op eq '--') {
					if ($ctx !~ /[WEOBC]x[^W]/ && $ctx !~ /[^W]x[WOBEC]/) {
						ERROR("SPACING",
						      "space required one side of that '$op' $at\n" . $hereptr);
					}
					if ($ctx =~ /Wx[BE]/ ||
					    ($ctx =~ /Wx./ && $cc =~ /^;/)) {
						ERROR("SPACING",
						      "space prohibited before that '$op' $at\n" . $hereptr);
					}
					if ($ctx =~ /ExW/) {
						ERROR("SPACING",
						      "space prohibited after that '$op' $at\n" . $hereptr);
					}


				# << and >> may either have or not have spaces both sides
				} elsif ($op eq '<<' or $op eq '>>' or
					 $op eq '&' or $op eq '^' or $op eq '|' or
					 $op eq '+' or $op eq '-' or
					 $op eq '*' or $op eq '/' or
					 $op eq '%')
				{
					if ($ctx =~ /Wx[^WCE]|[^WCE]xW/) {
						ERROR("SPACING",
						      "need consistent spacing around '$op' $at\n" .
							$hereptr);
					}

				# A colon needs no spaces before when it is
				# terminating a case value or a label.
				} elsif ($opv eq ':C' || $opv eq ':L') {
					if ($ctx =~ /Wx./) {
						ERROR("SPACING",
						      "space prohibited before that '$op' $at\n" . $hereptr);
					}

				# All the others need spaces both sides.
				} elsif ($ctx !~ /[EWC]x[CWE]/) {
					my $ok = 0;

					# Ignore email addresses <foo@bar>
					if (($op eq '<' &&
					     $cc =~ /^\S+\@\S+>/) ||
					    ($op eq '>' &&
					     $ca =~ /<\S+\@\S+$/))
					{
						$ok = 1;
					}

					# Ignore ?:
					if (($opv eq ':O' && $ca =~ /\?$/) ||
					    ($op eq '?' && $cc =~ /^:/)) {
						$ok = 1;
					}

					if ($ok == 0) {
						ERROR("SPACING",
						      "spaces required around that '$op' $at\n" . $hereptr);
					}
				}
				$off += length($elements[$n + 1]);
			}
		}

# check for multiple assignments
		if ($line =~ /^.\s*$Lval\s*=\s*$Lval\s*=(?!=)/) {
			CHK("MULTIPLE_ASSIGNMENTS",
			    "multiple assignments should be avoided\n" . $herecurr);
		}

## # check for multiple declarations, allowing for a function declaration
## # continuation.
##		if ($line =~ /^.\s*$Type\s+$Ident(?:\s*=[^,{]*)?\s*,\s*$Ident.*/ &&
##		    $line !~ /^.\s*$Type\s+$Ident(?:\s*=[^,{]*)?\s*,\s*$Type\s*$Ident.*/) {
##
##			# Remove any bracketed sections to ensure we do not
##			# falsly report the parameters of functions.
##			my $ln = $line;
##			while ($ln =~ s/\([^\(\)]*\)//g) {
##			}
##			if ($ln =~ /,/) {
##				WARN("MULTIPLE_DECLARATION",
##				     "declaring multiple variables together should be avoided\n" . $herecurr);
##			}
##		}

#need space before brace following if, while, etc
		if (($line =~ /\(.*\)\{/ && $line !~ /\($Type\)\{/) ||
		    $line =~ /do\{/) {
			ERROR("SPACING",
			      "space required before the open brace '{'\n" . $herecurr);
		}

# closing brace should have a space following it when it has anything
# on the line
		if ($line =~ /}(?!(?:,|;|\)))\S/) {
			ERROR("SPACING",
			      "space required after that close brace '}'\n" . $herecurr);
		}

# check spacing on square brackets
		if ($line =~ /\[\s/ && $line !~ /\[\s*$/) {
			ERROR("SPACING",
			      "space prohibited after that open square bracket '['\n" . $herecurr);
		}
		if ($line =~ /\s\]/) {
			ERROR("SPACING",
			      "space prohibited before that close square bracket ']'\n" . $herecurr);
		}

# check spacing on parentheses
		if ($line =~ /\(\s/ && $line !~ /\(\s*(?:\\)?$/ &&
		    $line !~ /for\s*\(\s+;/) {
			ERROR("SPACING",
			      "space prohibited after that open parenthesis '('\n" . $herecurr);
		}
		if ($line =~ /(\s+)\)/ && $line !~ /^.\s*\)/ &&
		    $line !~ /for\s*\(.*;\s+\)/ &&
		    $line !~ /:\s+\)/) {
			ERROR("SPACING",
			      "space prohibited before that close parenthesis ')'\n" . $herecurr);
		}

#goto labels aren't indented, allow a single space however
		if ($line=~/^.\s+[A-Za-z\d_]+:(?![0-9]+)/ and
		   !($line=~/^. [A-Za-z\d_]+:/) and !($line=~/^.\s+default:/)) {
			WARN("INDENTED_LABEL",
			     "labels should not be indented\n" . $herecurr);
		}

# Return is not a function.
		if (defined($stat) && $stat =~ /^.\s*return(\s*)(\(.*);/s) {
			my $spacing = $1;
			my $value = $2;

			# Flatten any parentheses
			$value =~ s/\(/ \(/g;
			$value =~ s/\)/\) /g;
			while ($value =~ s/\[[^\[\]]*\]/1/ ||
			       $value !~ /(?:$Ident|-?$Constant)\s*
					     $Compare\s*
					     (?:$Ident|-?$Constant)/x &&
			       $value =~ s/\([^\(\)]*\)/1/) {
			}
#print "value<$value>\n";
			if ($value =~ /^\s*(?:$Ident|-?$Constant)\s*$/) {
				ERROR("RETURN_PARENTHESES",
				      "return is not a function, parentheses are not required\n" . $herecurr);

			} elsif ($spacing !~ /\s+/) {
				ERROR("SPACING",
				      "space required before the open parenthesis '('\n" . $herecurr);
			}
		}
# Return of what appears to be an errno should normally be -'ve
		if ($line =~ /^.\s*return\s*(E[A-Z]*)\s*;/) {
			my $name = $1;
			if ($name ne 'EOF' && $name ne 'ERROR') {
				WARN("USE_NEGATIVE_ERRNO",
				     "return of an errno should typically be -ve (return -$1)\n" . $herecurr);
			}
		}

# Need a space before open parenthesis after if, while etc
		if ($line=~/\b(if|while|for|switch)\(/) {
			ERROR("SPACING", "space required before the open parenthesis '('\n" . $herecurr);
		}

# Check for illegal assignment in if conditional -- and check for trailing
# statements after the conditional.
		if ($line =~ /do\s*(?!{)/) {
			($stat, $cond, $line_nr_next, $remain_next, $off_next) =
				ctx_statement_block($linenr, $realcnt, 0)
					if (!defined $stat);
			my ($stat_next) = ctx_statement_block($line_nr_next,
						$remain_next, $off_next);
			$stat_next =~ s/\n./\n /g;
			##print "stat<$stat> stat_next<$stat_next>\n";

			if ($stat_next =~ /^\s*while\b/) {
				# If the statement carries leading newlines,
				# then count those as offsets.
				my ($whitespace) =
					($stat_next =~ /^((?:\s*\n[+-])*\s*)/s);
				my $offset =
					statement_rawlines($whitespace) - 1;

				$suppress_whiletrailers{$line_nr_next +
								$offset} = 1;
			}
		}
		if (!defined $suppress_whiletrailers{$linenr} &&
		    $line =~ /\b(?:if|while|for)\s*\(/ && $line !~ /^.\s*#/) {
			my ($s, $c) = ($stat, $cond);

			if ($c =~ /\bif\s*\(.*[^<>!=]=[^=].*/s) {
				ERROR("ASSIGN_IN_IF",
				      "do not use assignment in if condition\n" . $herecurr);
			}

			# Find out what is on the end of the line after the
			# conditional.
			substr($s, 0, length($c), '');
			$s =~ s/\n.*//g;
			$s =~ s/$;//g;	# Remove any comments
			if (length($c) && $s !~ /^\s*{?\s*\\*\s*$/ &&
			    $c !~ /}\s*while\s*/)
			{
				# Find out how long the conditional actually is.
				my @newlines = ($c =~ /\n/gs);
				my $cond_lines = 1 + $#newlines;
				my $stat_real = '';

				$stat_real = raw_line($linenr, $cond_lines)
							. "\n" if ($cond_lines);
				if (defined($stat_real) && $cond_lines > 1) {
					$stat_real = "[...]\n$stat_real";
				}

				ERROR("TRAILING_STATEMENTS",
				      "trailing statements should be on next line\n" . $herecurr . $stat_real);
			}
		}

# Check for bitwise tests written as boolean
		if ($line =~ /
			(?:
				(?:\[|\(|\&\&|\|\|)
				\s*0[xX][0-9]+\s*
				(?:\&\&|\|\|)
			|
				(?:\&\&|\|\|)
				\s*0[xX][0-9]+\s*
				(?:\&\&|\|\||\)|\])
			)/x)
		{
			WARN("HEXADECIMAL_BOOLEAN_TEST",
			     "boolean test with hexadecimal, perhaps just 1 \& or \|?\n" . $herecurr);
		}

# if and else should not have general statements after it
		if ($line =~ /^.\s*(?:}\s*)?else\b(.*)/) {
			my $s = $1;
			$s =~ s/$;//g;	# Remove any comments
			if ($s !~ /^\s*(?:\sif|(?:{|)\s*\\?\s*$)/) {
				ERROR("TRAILING_STATEMENTS",
				      "trailing statements should be on next line\n" . $herecurr);
			}
		}
# if should not continue a brace
		if ($line =~ /}\s*if\b/) {
			ERROR("TRAILING_STATEMENTS",
			      "trailing statements should be on next line\n" .
				$herecurr);
		}
# case and default should not have general statements after them
		if ($line =~ /^.\s*(?:case\s*.*|default\s*):/g &&
		    $line !~ /\G(?:
			(?:\s*$;*)(?:\s*{)?(?:\s*$;*)(?:\s*\\)?\s*$|
			\s*return\s+
		    )/xg)
		{
			ERROR("TRAILING_STATEMENTS",
			      "trailing statements should be on next line\n" . $herecurr);
		}

		# Check for }<nl>else {, these must be at the same
		# indent level to be relevant to each other.
		if ($prevline=~/}\s*$/ and $line=~/^.\s*else\s*/ and
						$previndent == $indent) {
			ERROR("ELSE_AFTER_BRACE",
			      "else should follow close brace '}'\n" . $hereprev);
		}

		if ($prevline=~/}\s*$/ and $line=~/^.\s*while\s*/ and
						$previndent == $indent) {
			my ($s, $c) = ctx_statement_block($linenr, $realcnt, 0);

			# Find out what is on the end of the line after the
			# conditional.
			substr($s, 0, length($c), '');
			$s =~ s/\n.*//g;

			if ($s =~ /^\s*;/) {
				ERROR("WHILE_AFTER_BRACE",
				      "while should follow close brace '}'\n" . $hereprev);
			}
		}

#studly caps, commented out until figure out how to distinguish between use of existing and adding new
#		if (($line=~/[\w_][a-z\d]+[A-Z]/) and !($line=~/print/)) {
#		    print "No studly caps, use _\n";
#		    print "$herecurr";
#		    $clean = 0;
#		}

#no spaces allowed after \ in define
		if ($line=~/\#\s*define.*\\\s$/) {
			WARN("WHITESPACE_AFTER_LINE_CONTINUATION",
			     "Whitepspace after \\ makes next lines useless\n" . $herecurr);
		}

#warn if <asm/foo.h> is #included and <linux/foo.h> is available (uses RAW line)
		if ($tree && $rawline =~ m{^.\s*\#\s*include\s*\<asm\/(.*)\.h\>}) {
			my $file = "$1.h";
			my $checkfile = "include/linux/$file";
			if (-f "$root/$checkfile" &&
			    $realfile ne $checkfile &&
			    $1 !~ /$allowed_asm_includes/)
			{
				if ($realfile =~ m{^arch/}) {
					CHK("ARCH_INCLUDE_LINUX",
					    "Consider using #include <linux/$file> instead of <asm/$file>\n" . $herecurr);
				} else {
					WARN("INCLUDE_LINUX",
					     "Use #include <linux/$file> instead of <asm/$file>\n" . $herecurr);
				}
			}
		}

# multi-statement macros should be enclosed in a do while loop, grab the
# first statement and ensure its the whole macro if its not enclosed
# in a known good container
		if ($realfile !~ m@/vmlinux.lds.h$@ &&
		    $line =~ /^.\s*\#\s*define\s*$Ident(\()?/) {
			my $ln = $linenr;
			my $cnt = $realcnt;
			my ($off, $dstat, $dcond, $rest);
			my $ctx = '';
			($dstat, $dcond, $ln, $cnt, $off) =
				ctx_statement_block($linenr, $realcnt, 0);
			$ctx = $dstat;
			#print "dstat<$dstat> dcond<$dcond> cnt<$cnt> off<$off>\n";
			#print "LINE<$lines[$ln-1]> len<" . length($lines[$ln-1]) . "\n";

			$dstat =~ s/^.\s*\#\s*define\s+$Ident(?:\([^\)]*\))?\s*//;
			$dstat =~ s/$;//g;
			$dstat =~ s/\\\n.//g;
			$dstat =~ s/^\s*//s;
			$dstat =~ s/\s*$//s;

			# Flatten any parentheses and braces
			while ($dstat =~ s/\([^\(\)]*\)/1/ ||
			       $dstat =~ s/\{[^\{\}]*\}/1/ ||
			       $dstat =~ s/\[[^\[\]]*\]/1/)
			{
			}

			# Flatten any obvious string concatentation.
			while ($dstat =~ s/("X*")\s*$Ident/$1/ ||
			       $dstat =~ s/$Ident\s*("X*")/$1/)
			{
			}

			my $exceptions = qr{
				$Declare|
				module_param_named|
				MODULE_PARAM_DESC|
				DECLARE_PER_CPU|
				DEFINE_PER_CPU|
				__typeof__\(|
				union|
				struct|
				\.$Ident\s*=\s*|
				^\"|\"$
			}x;
			#print "REST<$rest> dstat<$dstat> ctx<$ctx>\n";
			if ($dstat ne '' &&
			    $dstat !~ /^(?:$Ident|-?$Constant),$/ &&			# 10, // foo(),
			    $dstat !~ /^(?:$Ident|-?$Constant);$/ &&			# foo();
			    $dstat !~ /^[!~-]?(?:$Ident|$Constant)$/ &&		# 10 // foo() // !foo // ~foo // -foo
			    $dstat !~ /^'X'$/ &&					# character constants
			    $dstat !~ /$exceptions/ &&
			    $dstat !~ /^\.$Ident\s*=/ &&				# .foo =
			    $dstat !~ /^do\s*$Constant\s*while\s*$Constant;?$/ &&	# do {...} while (...); // do {...} while (...)
			    $dstat !~ /^for\s*$Constant$/ &&				# for (...)
			    $dstat !~ /^for\s*$Constant\s+(?:$Ident|-?$Constant)$/ &&	# for (...) bar()
			    $dstat !~ /^do\s*{/ &&					# do {...
			    $dstat !~ /^\(\{/)						# ({...
			{
				$ctx =~ s/\n*$//;
				my $herectx = $here . "\n";
				my $cnt = statement_rawlines($ctx);

				for (my $n = 0; $n < $cnt; $n++) {
					$herectx .= raw_line($linenr, $n) . "\n";
				}

				if ($dstat =~ /;/) {
					ERROR("MULTISTATEMENT_MACRO_USE_DO_WHILE",
					      "Macros with multiple statements should be enclosed in a do - while loop\n" . "$herectx");
				} else {
					ERROR("COMPLEX_MACRO",
					      "Macros with complex values should be enclosed in parenthesis\n" . "$herectx");
				}
			}
		}

# make sure symbols are always wrapped with VMLINUX_SYMBOL() ...
# all assignments may have only one of the following with an assignment:
#	.
#	ALIGN(...)
#	VMLINUX_SYMBOL(...)
		if ($realfile eq 'vmlinux.lds.h' && $line =~ /(?:(?:^|\s)$Ident\s*=|=\s*$Ident(?:\s|$))/) {
			WARN("MISSING_VMLINUX_SYMBOL",
			     "vmlinux.lds.h needs VMLINUX_SYMBOL() around C-visible symbols\n" . $herecurr);
		}

# check for redundant bracing round if etc
		if ($line =~ /(^.*)\bif\b/ && $1 !~ /else\s*$/) {
			my ($level, $endln, @chunks) =
				ctx_statement_full($linenr, $realcnt, 1);
			#print "chunks<$#chunks> linenr<$linenr> endln<$endln> level<$level>\n";
			#print "APW: <<$chunks[1][0]>><<$chunks[1][1]>>\n";
			if ($#chunks > 0 && $level == 0) {
				my @allowed = ();
				my $allow = 0;
				my $seen = 0;
				my $herectx = $here . "\n";
				my $ln = $linenr - 1;
				for my $chunk (@chunks) {
					my ($cond, $block) = @{$chunk};

					# If the condition carries leading newlines, then count those as offsets.
					my ($whitespace) = ($cond =~ /^((?:\s*\n[+-])*\s*)/s);
					my $offset = statement_rawlines($whitespace) - 1;

					$allowed[$allow] = 0;
					#print "COND<$cond> whitespace<$whitespace> offset<$offset>\n";

					# We have looked at and allowed this specific line.
					$suppress_ifbraces{$ln + $offset} = 1;

					$herectx .= "$rawlines[$ln + $offset]\n[...]\n";
					$ln += statement_rawlines($block) - 1;

					substr($block, 0, length($cond), '');

					$seen++ if ($block =~ /^\s*{/);

					#print "cond<$cond> block<$block> allowed<$allowed[$allow]>\n";
					if (statement_lines($cond) > 1) {
						#print "APW: ALLOWED: cond<$cond>\n";
						$allowed[$allow] = 1;
					}
					if ($block =~/\b(?:if|for|while)\b/) {
						#print "APW: ALLOWED: block<$block>\n";
						$allowed[$allow] = 1;
					}
					if (statement_block_size($block) > 1) {
						#print "APW: ALLOWED: lines block<$block>\n";
						$allowed[$allow] = 1;
					}
					$allow++;
				}
				if ($seen) {
					my $sum_allowed = 0;
					foreach (@allowed) {
						$sum_allowed += $_;
					}
					if ($sum_allowed == 0) {
						WARN("BRACES",
						     "braces {} are not necessary for any arm of this statement\n" . $herectx);
					} elsif ($sum_allowed != $allow &&
						 $seen != $allow) {
						CHK("BRACES",
						    "braces {} should be used on all arms of this statement\n" . $herectx);
					}
				}
			}
		}
		if (!defined $suppress_ifbraces{$linenr - 1} &&
					$line =~ /\b(if|while|for|else)\b/) {
			my $allowed = 0;

			# Check the pre-context.
			if (substr($line, 0, $-[0]) =~ /(\}\s*)$/) {
				#print "APW: ALLOWED: pre<$1>\n";
				$allowed = 1;
			}

			my ($level, $endln, @chunks) =
				ctx_statement_full($linenr, $realcnt, $-[0]);

			# Check the condition.
			my ($cond, $block) = @{$chunks[0]};
			#print "CHECKING<$linenr> cond<$cond> block<$block>\n";
			if (defined $cond) {
				substr($block, 0, length($cond), '');
			}
			if (statement_lines($cond) > 1) {
				#print "APW: ALLOWED: cond<$cond>\n";
				$allowed = 1;
			}
			if ($block =~/\b(?:if|for|while)\b/) {
				#print "APW: ALLOWED: block<$block>\n";
				$allowed = 1;
			}
			if (statement_block_size($block) > 1) {
				#print "APW: ALLOWED: lines block<$block>\n";
				$allowed = 1;
			}
			# Check the post-context.
			if (defined $chunks[1]) {
				my ($cond, $block) = @{$chunks[1]};
				if (defined $cond) {
					substr($block, 0, length($cond), '');
				}
				if ($block =~ /^\s*\{/) {
					#print "APW: ALLOWED: chunk-1 block<$block>\n";
					$allowed = 1;
				}
			}
			if ($level == 0 && $block =~ /^\s*\{/ && !$allowed) {
				my $herectx = $here . "\n";
				my $cnt = statement_rawlines($block);

				for (my $n = 0; $n < $cnt; $n++) {
					$herectx .= raw_line($linenr, $n) . "\n";
				}

				WARN("BRACES",
				     "braces {} are not necessary for single statement blocks\n" . $herectx);
			}
		}

# no volatiles please
		my $asm_volatile = qr{\b(__asm__|asm)\s+(__volatile__|volatile)\b};
		if ($line =~ /\bvolatile\b/ && $line !~ /$asm_volatile/) {
			WARN("VOLATILE",
			     "Use of volatile is usually wrong: see Documentation/volatile-considered-harmful.txt\n" . $herecurr);
		}

# warn about #if 0
		if ($line =~ /^.\s*\#\s*if\s+0\b/) {
			CHK("REDUNDANT_CODE",
			    "if this code is redundant consider removing it\n" .
				$herecurr);
		}

# check for needless kfree() checks
		if ($prevline =~ /\bif\s*\(([^\)]*)\)/) {
			my $expr = $1;
			if ($line =~ /\bkfree\(\Q$expr\E\);/) {
				WARN("NEEDLESS_KFREE",
				     "kfree(NULL) is safe this check is probably not required\n" . $hereprev);
			}
		}
# check for needless usb_free_urb() checks
		if ($prevline =~ /\bif\s*\(([^\)]*)\)/) {
			my $expr = $1;
			if ($line =~ /\busb_free_urb\(\Q$expr\E\);/) {
				WARN("NEEDLESS_USB_FREE_URB",
				     "usb_free_urb(NULL) is safe this check is probably not required\n" . $hereprev);
			}
		}

# prefer usleep_range over udelay
		if ($line =~ /\budelay\s*\(\s*(\w+)\s*\)/) {
			# ignore udelay's < 10, however
			if (! (($1 =~ /(\d+)/) && ($1 < 10)) ) {
				CHK("USLEEP_RANGE",
				    "usleep_range is preferred over udelay; see Documentation/timers/timers-howto.txt\n" . $line);
			}
		}

# warn about unexpectedly long msleep's
		if ($line =~ /\bmsleep\s*\((\d+)\);/) {
			if ($1 < 20) {
				WARN("MSLEEP",
				     "msleep < 20ms can sleep for up to 20ms; see Documentation/timers/timers-howto.txt\n" . $line);
			}
		}

# warn about #ifdefs in C files
#		if ($line =~ /^.\s*\#\s*if(|n)def/ && ($realfile =~ /\.c$/)) {
#			print "#ifdef in C files should be avoided\n";
#			print "$herecurr";
#			$clean = 0;
#		}

# warn about spacing in #ifdefs
		if ($line =~ /^.\s*\#\s*(ifdef|ifndef|elif)\s\s+/) {
			ERROR("SPACING",
			      "exactly one space required after that #$1\n" . $herecurr);
		}

# check for spinlock_t definitions without a comment.
		if ($line =~ /^.\s*(struct\s+mutex|spinlock_t)\s+\S+;/ ||
		    $line =~ /^.\s*(DEFINE_MUTEX)\s*\(/) {
			my $which = $1;
			if (!ctx_has_comment($first_line, $linenr)) {
				CHK("UNCOMMENTED_DEFINITION",
				    "$1 definition without comment\n" . $herecurr);
			}
		}
# check for memory barriers without a comment.
		if ($line =~ /\b(mb|rmb|wmb|read_barrier_depends|smp_mb|smp_rmb|smp_wmb|smp_read_barrier_depends)\(/) {
			if (!ctx_has_comment($first_line, $linenr)) {
				CHK("MEMORY_BARRIER",
				    "memory barrier without comment\n" . $herecurr);
			}
		}
# check of hardware specific defines
		if ($line =~ m@^.\s*\#\s*if.*\b(__i386__|__powerpc64__|__sun__|__s390x__)\b@ && $realfile !~ m@include/asm-@) {
			CHK("ARCH_DEFINES",
			    "architecture specific defines should be avoided\n" .  $herecurr);
		}

# Check that the storage class is at the beginning of a declaration
		if ($line =~ /\b$Storage\b/ && $line !~ /^.\s*$Storage\b/) {
			WARN("STORAGE_CLASS",
			     "storage class should be at the beginning of the declaration\n" . $herecurr)
		}

# check the location of the inline attribute, that it is between
# storage class and type.
		if ($line =~ /\b$Type\s+$Inline\b/ ||
		    $line =~ /\b$Inline\s+$Storage\b/) {
			ERROR("INLINE_LOCATION",
			      "inline keyword should sit between storage class and type\n" . $herecurr);
		}

# Check for __inline__ and __inline, prefer inline
		if ($line =~ /\b(__inline__|__inline)\b/) {
			WARN("INLINE",
			     "plain inline is preferred over $1\n" . $herecurr);
		}

# Check for __attribute__ packed, prefer __packed
		if ($line =~ /\b__attribute__\s*\(\s*\(.*\bpacked\b/) {
			WARN("PREFER_PACKED",
			     "__packed is preferred over __attribute__((packed))\n" . $herecurr);
		}

# Check for __attribute__ aligned, prefer __aligned
		if ($line =~ /\b__attribute__\s*\(\s*\(.*aligned/) {
			WARN("PREFER_ALIGNED",
			     "__aligned(size) is preferred over __attribute__((aligned(size)))\n" . $herecurr);
		}

# Check for __attribute__ format(printf, prefer __printf
		if ($line =~ /\b__attribute__\s*\(\s*\(\s*format\s*\(\s*printf/) {
			WARN("PREFER_PRINTF",
			     "__printf(string-index, first-to-check) is preferred over __attribute__((format(printf, string-index, first-to-check)))\n" . $herecurr);
		}

# Check for __attribute__ format(scanf, prefer __scanf
		if ($line =~ /\b__attribute__\s*\(\s*\(\s*format\s*\(\s*scanf\b/) {
			WARN("PREFER_SCANF",
			     "__scanf(string-index, first-to-check) is preferred over __attribute__((format(scanf, string-index, first-to-check)))\n" . $herecurr);
		}

# check for sizeof(&)
		if ($line =~ /\bsizeof\s*\(\s*\&/) {
			WARN("SIZEOF_ADDRESS",
			     "sizeof(& should be avoided\n" . $herecurr);
		}

# check for line continuations in quoted strings with odd counts of "
		if ($rawline =~ /\\$/ && $rawline =~ tr/"/"/ % 2) {
			WARN("LINE_CONTINUATIONS",
			     "Avoid line continuations in quoted strings\n" . $herecurr);
		}

# Check for misused memsets
		if ($^V && $^V ge 5.10.0 &&
		    defined $stat &&
		    $stat =~ /^\+(?:.*?)\bmemset\s*\(\s*$FuncArg\s*,\s*$FuncArg\s*\,\s*$FuncArg\s*\)/s) {

			my $ms_addr = $2;
			my $ms_val = $7;
			my $ms_size = $12;

			if ($ms_size =~ /^(0x|)0$/i) {
				ERROR("MEMSET",
				      "memset to 0's uses 0 as the 2nd argument, not the 3rd\n" . "$here\n$stat\n");
			} elsif ($ms_size =~ /^(0x|)1$/i) {
				WARN("MEMSET",
				     "single byte memset is suspicious. Swapped 2nd/3rd argument?\n" . "$here\n$stat\n");
			}
		}

# typecasts on min/max could be min_t/max_t
		if ($^V && $^V ge 5.10.0 &&
		    defined $stat &&
		    $stat =~ /^\+(?:.*?)\b(min|max)\s*\(\s*$FuncArg\s*,\s*$FuncArg\s*\)/) {
			if (defined $2 || defined $7) {
				my $call = $1;
				my $cast1 = deparenthesize($2);
				my $arg1 = $3;
				my $cast2 = deparenthesize($7);
				my $arg2 = $8;
				my $cast;

				if ($cast1 ne "" && $cast2 ne "" && $cast1 ne $cast2) {
					$cast = "$cast1 or $cast2";
				} elsif ($cast1 ne "") {
					$cast = $cast1;
				} else {
					$cast = $cast2;
				}
				WARN("MINMAX",
				     "$call() should probably be ${call}_t($cast, $arg1, $arg2)\n" . "$here\n$stat\n");
			}
		}

# check for new externs in .c files.
		if ($realfile =~ /\.c$/ && defined $stat &&
		    $stat =~ /^.\s*(?:extern\s+)?$Type\s+($Ident)(\s*)\(/s)
		{
			my $function_name = $1;
			my $paren_space = $2;

			my $s = $stat;
			if (defined $cond) {
				substr($s, 0, length($cond), '');
			}
			if ($s =~ /^\s*;/ &&
			    $function_name ne 'uninitialized_var')
			{
				WARN("AVOID_EXTERNS",
				     "externs should be avoided in .c files\n" .  $herecurr);
			}

			if ($paren_space =~ /\n/) {
				WARN("FUNCTION_ARGUMENTS",
				     "arguments for function declarations should follow identifier\n" . $herecurr);
			}

		} elsif ($realfile =~ /\.c$/ && defined $stat &&
		    $stat =~ /^.\s*extern\s+/)
		{
			WARN("AVOID_EXTERNS",
			     "externs should be avoided in .c files\n" .  $herecurr);
		}

# check for pointless casting of kmalloc return
		if ($line =~ /\*\s*\)\s*[kv][czm]alloc(_node){0,1}\b/) {
			WARN("UNNECESSARY_CASTS",
			     "unnecessary cast may hide bugs, see http://c-faq.com/malloc/mallocnocast.html\n" . $herecurr);
		}

# check for multiple semicolons
		if ($line =~ /;\s*;\s*$/) {
		    WARN("ONE_SEMICOLON",
			 "Statements terminations use 1 semicolon\n" . $herecurr);
		}

# check for gcc specific __FUNCTION__
		if ($line =~ /__FUNCTION__/) {
			WARN("USE_FUNC",
			     "__func__ should be used instead of gcc specific __FUNCTION__\n"  . $herecurr);
		}

# check for use of yield()
		if ($line =~ /\byield\s*\(\s*\)/) {
			WARN("YIELD",
			     "Using yield() is generally wrong. See yield() kernel-doc (sched/core.c)\n"  . $herecurr);
		}

# check for semaphores initialized locked
		if ($line =~ /^.\s*sema_init.+,\W?0\W?\)/) {
			WARN("CONSIDER_COMPLETION",
			     "consider using a completion\n" . $herecurr);
		}

# recommend kstrto* over simple_strto* and strict_strto*
		if ($line =~ /\b((simple|strict)_(strto(l|ll|ul|ull)))\s*\(/) {
			WARN("CONSIDER_KSTRTO",
			     "$1 is obsolete, use k$3 instead\n" . $herecurr);
		}

# check for __initcall(), use device_initcall() explicitly please
		if ($line =~ /^.\s*__initcall\s*\(/) {
			WARN("USE_DEVICE_INITCALL",
			     "please use device_initcall() instead of __initcall()\n" . $herecurr);
		}

# check for various ops structs, ensure they are const.
		my $struct_ops = qr{acpi_dock_ops|
				address_space_operations|
				backlight_ops|
				block_device_operations|
				dentry_operations|
				dev_pm_ops|
				dma_map_ops|
				extent_io_ops|
				file_lock_operations|
				file_operations|
				hv_ops|
				ide_dma_ops|
				intel_dvo_dev_ops|
				item_operations|
				iwl_ops|
				kgdb_arch|
				kgdb_io|
				kset_uevent_ops|
				lock_manager_operations|
				microcode_ops|
				mtrr_ops|
				neigh_ops|
				nlmsvc_binding|
				pci_raw_ops|
				pipe_buf_operations|
				platform_hibernation_ops|
				platform_suspend_ops|
				proto_ops|
				rpc_pipe_ops|
				seq_operations|
				snd_ac97_build_ops|
				soc_pcmcia_socket_ops|
				stacktrace_ops|
				sysfs_ops|
				tty_operations|
				usb_mon_operations|
				wd_ops}x;
		if ($line !~ /\bconst\b/ &&
		    $line =~ /\bstruct\s+($struct_ops)\b/) {
			WARN("CONST_STRUCT",
			     "struct $1 should normally be const\n" .
				$herecurr);
		}

# use of NR_CPUS is usually wrong
# ignore definitions of NR_CPUS and usage to define arrays as likely right
		if ($line =~ /\bNR_CPUS\b/ &&
		    $line !~ /^.\s*\s*#\s*if\b.*\bNR_CPUS\b/ &&
		    $line !~ /^.\s*\s*#\s*define\b.*\bNR_CPUS\b/ &&
		    $line !~ /^.\s*$Declare\s.*\[[^\]]*NR_CPUS[^\]]*\]/ &&
		    $line !~ /\[[^\]]*\.\.\.[^\]]*NR_CPUS[^\]]*\]/ &&
		    $line !~ /\[[^\]]*NR_CPUS[^\]]*\.\.\.[^\]]*\]/)
		{
			WARN("NR_CPUS",
			     "usage of NR_CPUS is often wrong - consider using cpu_possible(), num_possible_cpus(), for_each_possible_cpu(), etc\n" . $herecurr);
		}

# check for %L{u,d,i} in strings
		my $string;
		while ($line =~ /(?:^|")([X\t]*)(?:"|$)/g) {
			$string = substr($rawline, $-[1], $+[1] - $-[1]);
			$string =~ s/%%/__/g;
			if ($string =~ /(?<!%)%L[udi]/) {
				WARN("PRINTF_L",
				     "\%Ld/%Lu are not-standard C, use %lld/%llu\n" . $herecurr);
				last;
			}
		}

# whine mightly about in_atomic
		if ($line =~ /\bin_atomic\s*\(/) {
			if ($realfile =~ m@^drivers/@) {
				ERROR("IN_ATOMIC",
				      "do not use in_atomic in drivers\n" . $herecurr);
			} elsif ($realfile !~ m@^kernel/@) {
				WARN("IN_ATOMIC",
				     "use of in_atomic() is incorrect outside core kernel code\n" . $herecurr);
			}
		}

# check for lockdep_set_novalidate_class
		if ($line =~ /^.\s*lockdep_set_novalidate_class\s*\(/ ||
		    $line =~ /__lockdep_no_validate__\s*\)/ ) {
			if ($realfile !~ m@^kernel/lockdep@ &&
			    $realfile !~ m@^include/linux/lockdep@ &&
			    $realfile !~ m@^drivers/base/core@) {
				ERROR("LOCKDEP",
				      "lockdep_no_validate class is reserved for device->mutex.\n" . $herecurr);
			}
		}

		if ($line =~ /debugfs_create_file.*S_IWUGO/ ||
		    $line =~ /DEVICE_ATTR.*S_IWUGO/ ) {
			WARN("EXPORTED_WORLD_WRITABLE",
			     "Exporting world writable files is usually an error. Consider more restrictive permissions.\n" . $herecurr);
		}
	}

	# If we have no input at all, then there is nothing to report on
	# so just keep quiet.
	if ($#rawlines == -1) {
		exit(0);
	}

	# In mailback mode only produce a report in the negative, for
	# things that appear to be patches.
	if ($mailback && ($clean == 1 || !$is_patch)) {
		exit(0);
	}

	# This is not a patch, and we are are in 'no-patch' mode so
	# just keep quiet.
	if (!$chk_patch && !$is_patch) {
		exit(0);
	}

	if (!$is_patch) {
		ERROR("NOT_UNIFIED_DIFF",
		      "Does not appear to be a unified-diff format patch\n");
	}
	if ($is_patch && $chk_signoff && $signoff == 0) {
		ERROR("MISSING_SIGN_OFF",
		      "Missing Signed-off-by: line(s)\n");
	}

	print report_dump();
	if ($summary && !($clean == 1 && $quiet == 1)) {
		print "$filename " if ($summary_file);
		print "total: $cnt_error errors, $cnt_warn warnings, " .
			(($check)? "$cnt_chk checks, " : "") .
			"$cnt_lines lines checked\n";
		print "\n" if ($quiet == 0);
	}

	if ($quiet == 0) {

		if ($^V lt 5.10.0) {
			print("NOTE: perl $^V is not modern enough to detect all possible issues.\n");
			print("An upgrade to at least perl v5.10.0 is suggested.\n\n");
		}

		# If there were whitespace errors which cleanpatch can fix
		# then suggest that.
		if ($rpt_cleaners) {
			print "NOTE: whitespace errors detected, you may wish to use scripts/cleanpatch or\n";
			print "      scripts/cleanfile\n\n";
			$rpt_cleaners = 0;
		}
	}

	if ($quiet == 0 && keys %ignore_type) {
	    print "NOTE: Ignored message types:";
	    foreach my $ignore (sort keys %ignore_type) {
		print " $ignore";
	    }
	    print "\n\n";
	}

	if ($clean == 1 && $quiet == 0) {
		print "$vname has no obvious style problems and is ready for submission.\n"
	}
	if ($clean == 0 && $quiet == 0) {
		print << "EOM";
$vname has style problems, please review.

If any of these errors are false positives, please report
them to the maintainer, see CHECKPATCH in MAINTAINERS.
EOM
	}

	return $clean;
}
