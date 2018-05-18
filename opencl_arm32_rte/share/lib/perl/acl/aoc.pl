# (C) 1992-2016 Intel Corporation.                            
# Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
# and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
# and/or other countries. Other marks and brands may be claimed as the property  
# of others. See Trademarks on intel.com for full list of Intel trademarks or    
# the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
# Your use of Intel Corporation's design tools, logic functions and other        
# software and tools, and its AMPP partner logic functions, and any output       
# files any of the foregoing (including device programming or simulation         
# files), and any associated documentation or information are expressly subject  
# to the terms and conditions of the Altera Program License Subscription         
# Agreement, Intel MegaCore Function License Agreement, or other applicable      
# license agreement, including, without limitation, that your use is for the     
# sole purpose of programming logic devices manufactured by Intel and sold by    
# Intel or its authorized distributors.  Please refer to the applicable          
# agreement for further details.                                                 
    


# Intel(R) FPGA SDK for OpenCL(TM) kernel compiler.
#  Inputs:  A .cl file containing all the kernels
#  Output:  A subdirectory containing: 
#              Design template
#              Verilog source for the kernels
#              System definition header file
#
# 
# Example:
#     Command:       aoc foobar.cl
#     Generates:     
#        Subdirectory foobar including key files:
#           *.v
#           <something>.qsf   - Quartus project settings
#           <something>.sopc  - SOPC Builder project settings
#           kernel_system.tcl - SOPC Builder TCL script for kernel_system.qsys 
#           system.tcl        - SOPC Builder TCL script
#
# vim: set ts=2 sw=2 et

      BEGIN { 
         unshift @INC,
            (grep { -d $_ }
               (map { $ENV{"ALTERAOCLSDKROOT"}.$_ }
                  qw(
                     /host/windows64/bin/perl/lib/MSWin32-x64-multi-thread
                     /host/windows64/bin/perl/lib
                     /share/lib/perl
                     /share/lib/perl/5.8.8 ) ) );
      };


use strict;
require acl::File;
require acl::Pkg;
require acl::Env;
require acl::Board_migrate;

my $prog = 'aoc';
my $emulatorDevice = 'EmulatorDevice'; #Must match definition in acl.h
my $return_status = 0;

#Filenames
my $input_file = undef; # might be relative or absolute
my @given_input_files; # list of input files specified on command line.
my $output_file = undef; # -o argument
my $output_file_arg = undef; # -o argument
my $srcfile = undef; # might be relative or absolute
my $objfile = undef; # might be relative or absolute
my $x_file = undef; # might be relative or absolute
my $pkg_file = undef;
my $absolute_srcfile = undef; # absolute path
my $absolute_efispec_file = undef; # absolute path of the EFI Spec file
my $absolute_profilerconf_file = undef; # absolute path of the Profiler Config file

#directories
my $orig_dir = undef; # absolute path of original working directory.
my $work_dir = undef; # absolute path of the project working directory

#library-related
my @lib_files;
my @lib_paths;
my @resolved_lib_files;
my @lib_bc_files = ();
my $created_shared_aoco = undef;

# Executables
my $clang_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-clang";
my $opt_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-opt";
my $link_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-link";
my $llc_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/aocl-llc";
my $sysinteg_exe = $ENV{'ALTERAOCLSDKROOT'}."/linux64/bin"."/system_integrator";
my $aocl_libedit_exe = "aocl library";

#Log files
my $fulllog = undef;

my $regtest_mode = 0;

#Flow control
my $parse_only = 0; # Hidden option to stop after clang.
my $opt_only = 0; # Hidden option to only run the optimizer
my $verilog_gen_only = 0; # Hidden option to only run the Verilog generator
my $ip_gen_only = 0; # Hidden option to only run up until ip-generate, used by sim
my $high_effort = 0;
my $skip_qsys = 0; # Hidden option to skip the Qsys generation of "system"
my $compile_step = 0; # stop after generating .aoco
my $vfabric_flow = 0;
my $griffin_flow = 0; # Use DSPBA backend instead of HDLGeneration
my $generate_vfabric = 0;
my $reuse_vfabrics = 0;
my $vfabric_seed = undef;
my $custom_vfab_lib_path = undef;
my $emulator_flow = 0;
my $soft_ip_c_flow = 0;
my $accel_gen_flow = 0;
my $run_quartus = 0;
my $hdl_comp_pkg_flow = 0; #Forward args from 'aoc' to 'aocl library'
my $c_acceleration = 0; # Hidden option to skip clang for C Acceleration flow.
my $simulation_mode = 0; #Hidden option to generate full board verilogs targeted for simulation  (aoc -s foo.cl)
my $no_automigrate = 0; #Hidden option to skip BSP Auto Migration


#Flow modifiers
my $optarea = 0;
my $force_initial_dir = '.'; # absolute path of original working directory the user told us to use.
my $use_ip_library = 1; # Should AOC use the soft IP library
my $use_ip_library_override = 1;
my $do_env_check = 1;
my $dsploc = '';
my $ramloc = '';

#Output control
my $verbose = 0; # Note: there are two verbosity levels now 1 and 2
my $report = 0; # Show Throughput and area analysis
my $estimate_throughput = 0; # Show Throughput guesstimate
my $debug = 0; # Show debug output from various stages
my $time_log = undef; # Time various stages of the flow; if not undef, it is a 
                      # file handle (could be STDOUT) to which the output is printed to.
my $time_passes = 0; # Time LLVM passes. Requires $time_log to be valid.
# Should we be tidy? That is, delete all intermediate output and keep only the output .aclx file?
# Intermediates are removed only in the --hw flow
my $dotfiles = 0;
my $tidy = 0; 
my $save_temps = 0;
my $pkg_save_extra = 0; # Save extra items in the package file: source, IR, verilog
my $library_debug = 0;

# Yet unclassfied
my $save_last_bc= 0; #don't remove final bc if we are generating profiles
my $disassemble = 0; # Hidden option to disassemble the IR
my $fit_seed = undef; # Hidden option to set fitter seed
my $profile = 0; # Option to enable profiling
my $program_hash = undef; # SHA-1 hash of program source, options, and board.
my $triple_arg = '';
my $dash_g = 1;      # Debug info enabled by default. Use -g0 to disable.
my $user_dash_g = 0; # Indicates if the user explictly compiled with -g.

# Regular arguments.  These go to clang, but does not include the .cl file.
my @user_clang_args = ();

# The compile options as provided by the clBuildProgram OpenCL API call.
# In a standard flow, the ACL host library will generate the .cl file name, 
# and the board spec, so they do not appear in this list.
my @user_opencl_args = ();

my $opt_arg_after   = ''; # Extra options for opt, after regular options.
my $llc_arg_after   = '';
my $clang_arg_after = '';
my $sysinteg_arg_after = '';

my $efispec_file = undef;
my $profilerconf_file = undef;
my $dft_opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frkzwewi22etqs0o0cvorlvczrk7mipp8xd3egwiyx713svzw3kmlt8clxdbqoypaxbbyw0oygu1nsyzekh3nt0x0jpsmvypfxguwwdo880qqk8pachqllyc18a7q3wp12j7eqwipxw13swz1bp7tk71wyb3rb17frk3egwiy2e7qjwoe3bkny8xrrdbq1w7ljg70g0o1xlbmupoecdfluu3xxf7l3dogxfs0lvm7jlzqjvo33gclly3xxf7mi8p32dc7udmirekmgvoy1bknyycrgfhmczpyxgf0wvz7jlzmy8p83kfnedxz2azqb17frk77qdiyxlkmh8ithkcluu3xxf7nvyzs2kmegdoyxlctgfptck3nt0318a7mcyz1xgu7uui3rezlg07ekh3lqjxtgdmnczpy2jtehdo3xyctgfpthjmljpbzgdmlb17frkuww0zwreeqapzkhholuu3xxf7nz8p3xguwypp3gw7mju7atjbnhdxmrjumipprxdceg0z880qqk8z2tk7qjjxbxacnzvpfxbbyw0otrebma8z2hdolkwx18a7m8jorxbbyw0o72eona8iekh3nyvb1rzbtijz82hkwhjibgwklgfptchqlyvc7rahm8w7ljg7wldzzxu13svz0cg1mt8c8gssmxw7ljg70tjzwgukmkyo03k7qjjxwgfzmb0ogrgswtfmirezqspo23kfnuwb1rdbtijz3gffwhpom2e3ldjpacvorlvcqgskq10pggju7ryomx713svzkhh3qhvccgammzpplxbbyw0ow2ekmavzuchfntwxzga33czpyrfu0evzp2qmqwvzltk72tfxm2kbmbjo8rg70qpow2wctgfptchhnl0b18a7q8vpm2kc7uvm7jlzma8pt3h72tfxmrafmiwoljg70kyitrykmrvzj3bknywbp2kbm8wpdxgc0uui0x1ctgfptchhnl0b18a7m3pp8rduwk0ovx713svzkhh3qhvccgammzpplxbbyw0obgl3mt8z2td72tfxmrafmiwoljg70qjobrlumju7atjfnljxwgpsmv0zlxgbwkpioglctgfpttkbql0318a7mo8zark37swiyxyctgfpttd3ny0b0jpsmvypfrfc7rwizgekmsyzy1bknypxuga3nczpyxdtwgdo1xwkmsjzy1bknyvcc2kmnc0prxdbwudmirecnujp83jcnuwbzxasqb17frkc0gdo880qqk8zwtjoluu3xxf7nz8p3xguwypp3gw7mju7atjqllvbyxffmodzgggbwtfmireznrpokcdorlvc8gd1qc87frk3egwiwrl3lw0oetd72tfxmxdhmidzrxgc0rdo880qqkvzshh3qhyx12kzmcw7ljg7wrporgukqgpoy1bknyvcc2aoncdom2vs0rpiogu3qgfpt3ghngpb18a7q3vpljg70qyiwgukmsvoktj3quu3xxfhmivolgfbyw0oy2qclgvoy1bknyybx2kfqo0pljg70rvi1glqqgwp3cvorlvc8xdon38zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7we0otrubmju7atjfnljxwgpsmv8ofgffweji880qqkwzbhh13jwb7rj33czpy2g10g0i12ectgfpttdqnq0bvgsom7jzerj38uui3ruzqk0oy1bknyjcr2a33czpy2gb0e0oy2temywoy1bkny8xxxkcnvvpagkuwwdo880qqkpp73h7mtfxmrjtq88zrxjuwwwo880qqkwz33k72tfxmgfcmv8zt8vs0r0zb2lcna8pl3a3lrjc0jpsmvypfrfc7rwizgekmsyzy1bknyvby2kuq187frkc0upo020qqk0o2thzmlwbfrkbm8w7ljg70yjiogebmawzt3k72tfxmxffqijom2gbwgwo7x713svzr3j1qj8x12k33czpy2jo0qdmirecls8pacfoljy3xxf1q8vzljg70tyi1xlklu8p3cvorlvc7raznbyi82vs0rpiixlkmsyzy1bknydxc2kkq88zmxbbyw0oz2wolhyz23kzmhpbxrzbtijzgggc7u8zn2ezqgvoy1bknywc32jbncw7ljg7wh8zo2lemryz3cfmlh8xmxk33czpy2k7wedmiretqs8zw3bknyvbyxamnc87frkuwwjzr2qqqu8pttdorlvc7rdcqb17frkt0tyi0xl1qgfpt3kbnevc7rahm8w7ljg7wk8z1glznhjp23horlvc12dumvyzsxg7etfmiretqsjoehd3nldxrrzbtijzqrkbwtfmiretqsjoehd3nldxqrj33czpy2kh0jpokru13svz23ksnldb1gpsmv8pl2gbyw0obgl3nu8patdqnyvb0jpsmvdol2gfwjdo7jlzqsjpr3bkny8cmxfbm8jolrf38uui3xwzqg07ekh3njvc7ra1q8dolxfhwtfmire3qkyzy1bkny0blgsol8folrj38uui3gu1qajpn3korlvcz2auq3yprxguwapow2qemsy7atj3qhjxlgd7lb17frk3egwizrl3lg0o23gbquu3xxf1qcjzlxbbyw0oprlemyy7atj3meyxwrauqxyit8vs0rvzv2q13svztthmlqycqxfuqivzt8vs0r0zb2lcna8pl3a3lrjc0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpygjuwsdzy20qqkpzkcf3nuvbyxk33czpyxgk0udi7jlzqu0od3gzqhyclrzbtijz72jm7qyokx713svzucfzqj8xngjcncwo1rg37two1xykqsdpy1bknyjcr2a33czpyxjzwjdz7x713svzwtjoluu3xxf7nz8p3xguwypp3gw7mju7atjfnjwblgj7q3ype2s38uui32qqquwotthsly8xxgdbtijzfrgbyw0olx713svz3tjmlq8clgsqnc87frkh0t8zm2w13svzutkcljyc3gfcncjot8vs0r0z32etqjpo23k7qq0318a7qcjzlxbbyw0on2qhlr0oekh3ly8xyxf1m80o8xbbyw0oprl7lgpo3tfqlhvcprzbtijz8rk1wepor2qslg07ekh3lljxlgahm8w7ljg7wu0o7x713svzuck3nt0318a7mxpofxbbyw0o0re1mju7atjqllvbyxffmodzgggbwtfmirecnujpqhdmnqy3xxfzqovpu2kh0uui32l1qa07ekh3lkpbcxdmnb8pljg70yjiogebmay7atjsntyx18a7m3jorrjbwtfmire3nu8pn3gmlqy3xxfkmb0ohxbbyw0omgyqmju7atj3meyxwrauqxyiljg7wyvz880qqkwzt3k72tfxmgssqc8zcrfz7tvzy2qqqh07ekh3ng8xzxfkqb17frkcegpoirumqspof3bkny0blgssq3pzt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7we0otrubmju7atjsntwxcxa3lb17frko7u8zbgwknju7atjfnljxwgpsmvjog2g3eepin2tctgfptch3njvb7rzbtijzugkowgdou20qqk8zahhhlh8cygd33czpyxjfwkdmirezmhjzekh3lypc22kbm1w7ljg7wr8z1glzmdy7atj3nldxrgdmn8ypdggmutfmire3qkyzy1bkny8xxxkcnvvpagkuwwdo880qqk0oj3gorlvcmxa1qo8z8rkuwwwo880qqkdoetjzmlpbz2hbmczpyrhbwgyi7xlctgfpthfolj8x2gh33czpyrjoewvm7jlzqddp3cf3nlyxngssmcw7ljg7wu0o7x713svzn3k1medcfrzbtijz12jk0wyz720qqkwze3jzntfxmxkcnidolrf38uui3xwzqg07ekh3lqjxcrkbtijzq2jh0ujzbrlqmju7atjbmtpbz2dulb17frkk0u8zm2w13svz8hdolt8xmgfcnc0zljg70gjzogu1qu07ekh3ltvc1rzbtijzggg7ek0oo2loqddpecvorlvclgd3loypy2kc7udmiretquyoy1bkny8c8xfbqb17frkh0q0ozx713svzdthhlky3xxf7mi8pu2hs0uvm7jlzma8pt3h72tfxm2jbq8ype2s38uui3xleqs0oekh3lhpbzrk7mi8ofxdbyw0o1glqqswoucfoluu3xxf7qvwot8vs0ryz7gukmh8iy1bkny8xxxkcnvvpagkuwwdo880qqkjznhh72tfxmxkumowos2ho0s0onrwctgfpt3holjjc12kbq38o1gg38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxmxdoliw7ljg7wk8zbgykqjwpekh3nq8cyrs33czpyxj70uvm7jlzmtyz23gbnf0318a7q88zq2d70udmireolgvos3f1myycqrzbtijzqrkbwtfmiremlgpokhkqquu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcqgskq10pggju7ryomx713svzdthcmtpbqxjuq3jzhxbbyw0o3xqbmsdpechorlvcngfml8yplgfbyw0obglzlgpo03ghll0318a7qoypy2g38uui32lcng07ekh3nudxxxacnb0ol2vs0r0oo2etqgvot3gknry3xxfmmi8ofxj7etfmirecldvzh3bknyyx1gabtijzyrgswypimx713svzn3k1medcfrzbtijzs2h70evm7jlzqt8pktjsluu3xxfhmiyzqrfc7w8z7ru3lwwpecvorlvcvxjzqoypfrfbwgjz880qqkpoe3hmlhyclgs1qoypb2j38uui3xwzqg07ekh3ly8cl2kumcdo8xdueedo880qqkwzt3k72tfxm2kbq3wp0rdz0qjo880qqkjokhh72tfxmxjfq8jpgxdb0edmirekmswo23gknj8xmxkbtijzsrgz7u8z7guctgfpt3honqjxlgh7l3dol2kk0qyimx713svzdthmltvbyxamncjom2sh0uvm7jlzquvzuchmljpb1rdbnv0ogrgswtfmirezqsdpn3k1qhy3xxfuqi0olrjbwgdmireuqrwp03g7qq8x12k7lb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0rpo0gq1luwoekh3nj8xagd7lb17frko7u8zbgwknju7atjblky3xxf3n3joh2vs0rdiextctgfpthk7mtfxmrs1q80zlggbwuvm7jlzmhyo33korlvcy2kumxvpfrgk0ujzr2qzqgfpthkoqlvcygsfqijot8vs0ryoeru1qgfpt3jzltvbu2fbtijze2ds0rjzbrlqqu07ekh3ltjxu2fhmc87frk37kdiy20qqkdz83bknyybxgsclb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0ryoyre13svzw3k3nlyxwxa7nz0ogrgswtfmirekmsvo0tjhnqpcz2abqb17frkc0rdo880qqkdz8tjorlvcmxasq28z1rfu0wyi7jlzmyyo3cg72tfxm2d3nv87frk70wyil2wolu8pshhorlvclgdkmiporxg38uui32qqquwotthsly8xxgd33czpyxj70uvm7jlzmh0ot3bknywcf2a1moypy2vs0rpop2q7ms07ekh3nedxqrj7mi8pu2hs0uvm7jlzmgvzecvorlvc32jsqb17frk77qdiyxlkmh8ithkcluu3xxf7nz8p3xguwypp7jlzmh0oy1bknywcmgd33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg7wewioxu13svz33gslkwxz2dulb17frkm7ujoere1qgfptckolkycxrdbqijzl2vs0rjobru3ljdpt3k72tfxmgfml8yzx2vs0rvzr2qmnju7atj1mtyxc2jbmczpy2ds0jpoixy1mgy7atj3nuwxvxk33czpyxgf0tjotxyemuyz3cfqqqyc0jpsmvdodxgh0uui3xukmyyzd3gknt0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijzs2hk0qjz7jlzqkjpatjoqjpb12a7m7w7ljg70tyiirl3ljwoe3bknyyx1gacmcwot8vs0rpiiru1muwoekh3nj8vxxfbtijzu2dowydorructgfpt3jklljxygfcnc87frk7wqpoigl1may7atjznt0b12acmcppy2hb0gvm7jlzmh0oq3jqllwcrgfmn8w7ljg70g0obgyctgfpthkbngwc0jpsmvjosgd38uui3gekmry7atjsnudxzrk33czpyxfm7udmiretqsjp83bkny0bzrkbqoypf2hs0yvm7jlzmuyzfthbmty3xxfcm3wos2h70tjz720qqkwzrtk72tfxmxdoliw7ljg70qyitxyzqsypr3gknt0318a7qcypfxdbwtfmirebmgvzecvorlvcqxfuq2w7ljg7wewioxu13svz83g7mtwxz2auqivzt8vs0rpiiru3lkjpfhjqllyc0jpsmv0zy2j38uui3gu1qajpn3korlvc8gj3loypy2kc7udmire3mkjzy1bknyvbzga3loype2s7wywo880qqkwpstfoljvbtgscnvwpt8vs0rjooxy13svzthkcntfxmrafmiwoljg7whpiy2wtqddpkhhcluu3xxfzmcwoljg7wewiq2wolddpqcvorlvcz2a7l3jzd2gm0qyi7x713svz33gslkwxz2dunvpzwxbbyw0o0re1mju7atjblky3xxftmbdoq2js0ujo7jlzqjvzt3fsluu3xxfoq187frkt0t8z02wqqgwzekh3ltjxyrzbtijzggg7ek0oo2loqddpecvorlvcqgskq10pggju7ryomx713svzwtjoluu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcrgdmnzpzxxbbyw0onxleqjwokhhclkjxz2acn80oxxgbwtfmirezmuyzucfontfxmxkcnb0ps2vs0ryor2w1qgfpttjfnhvbygdmn8w7ljg70gdop2wzmry7atj3le8cz2abtijzdxfcetfmire3qkyzy1bkny8xxxkcnvvpagkuwwdo880qqk8zwhgomjwb18a7m8ypb2j7etfmiremlgpokhkqquu3xxfmnc0znrkb0uui3gwbmsjp7cf72tfxm2fmncyzj2vs0rdi72l3qg0oy1bknywcmgd33czpygfb0gwieguzqgy7atj3qe8clgssmxw7ljg70rji72eqqr0oekh3njjx2rjbtijzgxf38uui3xyhmujp7tkelkybygpsmvwo12hswkvm7jlzmtyz23gbnf0318a7qxwow2ko7u8zbgwknjf0a';
my $soft_ip_opt_passes = '--acle ljg7wk8o12ectgfpthjmnj8xmgf1qb17frk77qdiyxlkmh8ithkcluu3xxf7nvyzs2kmegdoyxlctgfpt3kmljwxfgpsmvjz82j38uui3xleqtyz23bknyycdrkbmv0ot8vs0r8o1guoldyz2cvorlvc3rafqvyzsrg3ekvm7jlzqd0otthknjwbw2kfq1w7ljg7wudo1xwbmujzechqnq0318a7mzpp8xd70wdi22qqqg07ekh3nj8xbrkhmzpzxrko0yvm7jlzmypo7hhontfxmgdtqb17frkuwwjibgl1mju7atjqllwxz2abmczpyxdtwgdotxqemawzekhznk71wyb3r1em3vbbyw0on2yqqkwokthknuwby2k7lb17frk1wgwoygueqajp03ghll0318a7m8jzrxg1wg8z7xutqgfpttd3mu0318a7mcyz1xgu7uui3rezlg07ekh3nj8xbrkhmzpzx2vs0rjibgezqjwpdtd72tfxm2sbnowoljg7wkvir2wbmg8patk72tfxmgfcl3doggkbekdoyguemy8zq3jzmejxxrzbtijzyrgmegdop2e3lgwzekh3lkpbcrk1mxyzm2hfwwvm7jlzqu8pfcdfnedcfxfomxw7ljg70qyitxyzqsypr3gknt0318a7q3yzgxg70tjip2wtqdypy1bknyvbzga3loype2s7wywo880qqkpoe3j3mjjxmgs1q38zt8vs0rjiorlclgfpthdhlh8cygd33czpyxgu0rdi880qqkwpsth7mtfxmgjsm8vogxd7wqdmire3ndpoetdenlwx8gpsqcwmt8vs0rjiorlclgfpt3fknjjbzrj7qzw7ljg70qyitxyzqsypr3gknt0318a7mzppqgd1wg0z880qqkwpsth7mtfxmgscmzvpaxbbyw0oprlemyy7atjzntwx1rjumippt8vs0rwolglctgfpt3honqvcwghfq10ot8vs0r0z3recnju7atjqllvbyxffmodzgggbwtfmiresqryp83bknywbp2kbmb0zgggzwtfmirezqspo23kfnuwb1rdbtijz3gffwhpom2e3ldjpacvorlvc8xkbqb17frk1wu0o7x713svz33gslkwxz2dunvpzwxbbyw0obglznrvzs3h1nedx1rzbtijz8xdm7qvz7jlzmgyzuckorlvcw2kfq3vpm2s37u0z880qqkjzdth1nuwx8xfbqb17frk70wyitxyuqgpoq3k72tfxm2f1q8dog2jmetfmiretqsjp83bknyvbzga3loype2s38uui3xlzquvoucvorlvcvxafq187frkbew8zoxltmju7atjclgdx0jpsmv8pl2g7whppoxu3nju7atj3myvcwrzbtijzggg7ek0oo2loqddpecvorlvcigjkq187frkceq8z72e3qddpqcvorlvcmxaml88zs2kc7ujo7jlzmyposcdmnr8cygsfqiw7ljg7wu0z7x713svzuck3nt0318a7m8ypaxfh0qyokremqh07ekh3nedxqrj7mi8pu2hs0uvm7jlzquwo23g7mtfxmrdbmb0zljg7wh8zoxyemr8i83k3quu3xxfzqovpu2khwu0o7x713svztthknjwbbgdmnx8zt8vs0r8o1guoldyz2cvorlvc7raznbyi82vs0rpiixlkmsyzy1bknyvby2kuq1ppjxbbyw0oirlolapoecf72tfxmrdzq28olxbbyw0o1retqgfptchhnuwc18a7m80odgfb0uui32qqmrpokhh3mevcqgpsmvyzqxj38uui3reemsdoehdzmtfxmgsfq80zljg70qwiqgu13svz0thorlvcz2acl8ypfrfu0r0z880qqkwpstfoljvcc2aolb17frkc0rdo880qqkwpstfoljvcc2a7l3w7ljg70tjiq2ekluy7atj1mtyxc2jbmczpy2gb0edmirekmswo23gknj8xmxk33czpyrf70tji1guolg0odcvorlvcw2kuq2dm12jzwtfmirecnujpfthzmt0blgsolb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0ryobxt1nyy7atj1newbmgf7l3jot8vs0rjiz2wuqgfpttd7qq8xyrjbq8w7ljg7wjdor2qmqw07ekh3lljxlgahm8w7ljg70tjzwgukmkyo03k7qjjxwgfzmb0ogrgswtfmire7mtdpy1bknywcmgd33czpyrfu0evzp2qmqwvzltk72tfxmra7l3donrkc7qyokx713svzkhh3qhvccgammzppl2vs0ryio20qqkdoy1bknyvbmgfhmbdoggsb0uui3xlbmujze3bkny8c3xdmncvzrxdb0gvm7jlzquvzuchmljpb1rkhqb17frko0qvpexu13svzr3gzmy8cqrj7lb17frkh0wwz7guzlt8p0tjeluu3xxf7nvyzs2km7q8p7x713svzwtjoluu3xxf1qcjzlxbbyw0omgyqmju7atjznyyc0jpsmvypfrfc7rwizgekmsyzy1bkny0blxazq8yza2vs0rwoprloqjwpekh3nqycbrzbtijz3gff0y8z12l13svzqchhly8cvgpsmv8pl2gbyw0oerubqhyzy1bknywblgsonzyzs2vs0rdi1xyhmju7atj3meyxwrauqxyiljg7wyvz880qqkwzt3k72tfxmgssqc8zcrfz7tvzy2qqqh07ekh3lhpb72a7lxvp12gbyw0oygukmswolcvorlvcvxafq187frk77qdiyxlkmh8iy1bknywxmxk7nbw7ljg70gdoprlemy07ekh3lypc22kbm187frk1wwyioxybmryzy1bknywccrjbtijzygjz0uui3geomhpoe3d72tfxmxkumowos2ho0s0onrwctgfpt3holjjc12kbq38o1gg38uui3geoljdptcgorlvcmxasq28z1rfu0wyirv713svzwtjoluu3xxfuqijomrkf0e8obgl1mju7atjbmtvcyxamnzdil2vs0r0i7guqqgwpy1bknydb12kuqxyit8vs0rwolglctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3lgyclgsom7w7ljg7wgdozrlmlgy7atjznt8c8gpsmvjomrgm7u0z880qqkwzt3k72tfxm2jbq8ype2s38uui32l1mujze3bkny0blgdcmzjzrxdbwudmireznrjp23k3quu3xxfcmv8zt8vs0rpiiru3lkjpfhjqllyc0jpsmvyzfggfwkpow2w13svztthmlqycqxfuqivzljg7wrwiegl3qu07ekh3nwycl2abqo87frkc0kvzp2qzqjwoshd72tfxmrd7mcw7ljg7wjdor2qmqw07ekh3nqycbxamn7jzd2kh0u0z32qqqh07ekh3lgyclgsom7w7ljg70yyzix713svzwtjoluu3xxfoncdoggjuetfmirezlk8zd3j1qjyc8gj7q3ypdgg38uui3xlkqkypy1bknywxcxa3nczpyrkf0e8obgl1mju7atjfnevcbrzbtijza2jm7ydor2w3lrpoacvorlvcqgskq10pggju7ryomx713svzdthcmtpbqxjuq3jzhxbbyw0omgyqmju7atjzqj8xrgs1qo87frkk0tjzvx713svzwtjoluu3xxf7nc0orxgu0yyiz2wqmrvoy1bknydb12kuqxyit8vs0r8z7xw1lkyzekh3ljycqxabl8jzlrf38uui3xwzqg07ekh3lgyclgsom7w7ljg70tjox2yznry7atj3mepv1xk33czpyrfu0evzp2qmqwvzltk72tfxmrafm28z1rfz7qjz3xqctgfpttfqll0318a7qvyz1gfu0u8ztxyknayzy1bkny8xxxkcnvvpagkuwwdo880qqkwzt3k72tfxmgabmo87frkm0tyic20qqk0oshdzmtfxmgf7n8ypwggk0uyiwx713svzdthmltvbyxamncjom2sh0uvm7jlzmajoqchqllvb12kclb17frkm7udi1xy1mu8puchqldyc0jpsmv0zy2j38uui3xleqjwz3cfhljycqrjulo8zt8vs0rjzvgueqrjzjcdoqhy3xxf1qippdxd1wkdo880qqkvpehdkntwx18a7m88zs2j7wkwirx713svzwtjoluu3xxfoncdoggjuetfmirezqsdpn3k1qhy3xxfuqi0olrjbwgdmireuqrwp03g7qq8x12k7lb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0rpo0gq1luwoekh3nj8xagd7lb17frko7u8zbgwknju7atjbnhvb1gpsmv0o12hz0wyio2l1mrpoktjorlvc2gjsmv0ogrgs0gvm7jlzmgjp7hjfnty3xxf3n38p32vs0ryoy20qqkyoa3gzquu3xxfuqijomrkf0e8obgl1mju7atjznyyc0jpsmvpz3rkbyw0o02wzqsyp8th3mewbzxasqb17frkuww0zwreeqapzkhholuu3xxfcmv8zt8vs0ryoyre13svztthklgyclxkumippljg7wgdozrlmljwpy1bkny8xxxkcnvvpagkuwwdo880qqkwzt3k72tfxm2d3nv87frkc0syi12lkqky7atjmlq8x32a33czpy2hs0gjz3rlumk8pa3k72tfxmrd7mcw7ljg70gpizxutqddzb3bknydcwrzbtijzqrkbwtfmirebmgpp7tdzmtfxmxkuq08z8xbbyw0ol2wolddzbcvorlvc2rafmb0ogggzwhwibgl3luwobcholuu3xxfbq7wodrfb0uui3xlkmtyzekh3lg8cvgjbm8w7ljg7wewioxu13svz83g7mtwxz2auqivzt8vs0rjo32wctgfpthdonjjxu2k7mc87frk7eqpor2qqqh07ekh3lh0xlxabnxwp32dc7uui3xuolddp0cvorlvcrgdmnzpzxxbbyw0onxu7qjdoehdqlr8v08is';

# device spec differs from board spec since it
# can only contain device information (no board specific parameters,
# like memory interfaces, etc)
my $device_spec = "";
my $soft_ip_c_name = "";
my $accel_name = "";

my $lmem_disable_split_flag = '-no-lms=1';
my $lmem_disable_replication_flag = ' -no-local-mem-replication=1';

# On Windows, always use 64-bit binaries.
# On Linux, always use 64-bit binaries, but via the wrapper shell scripts in "bin".
my $qbindir = ( $^O =~ m/MSWin/ ? 'bin64' : 'bin' );

# For messaging about missing executables
my $exesuffix = ( $^O =~ m/MSWin/ ? '.exe' : '' );

my $emulator_arch=acl::Env::get_arch();

# Types of IR that we may have
# AOCO sections in shared mode will have names of form:
#    $ACL_CLANG_IR_SECTION_PREFIX . $CLANG_IR_TYPE_SECT_NAME[ir_type]
my $ACL_CLANG_IR_SECTION_PREFIX = ".acl.clang_ir";
my @CLANG_IR_TYPE_SECT_NAME = (
  "fpga64",
  "fpga64be",
  "x86_64-unknown-linux-gnu",
  "x86_64-pc-win32"
);

my $QUARTUS_VERSION = undef; # Saving the output of quartus_sh --version globally to save time.
      
sub mydie(@) {
  print STDERR "Error: ".join("\n",@_)."\n";
  chdir $orig_dir if defined $orig_dir;
  unlink $pkg_file;
  exit 1;
}

sub move_to_log { #string, filename ..., logfile
  my $string = shift @_;
  my $logfile= pop @_;
  open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
  print LOG $string."\n" if ($string && ($verbose > 1 || $save_temps));
  foreach my $infile (@_) {
    open(TMP, "<$infile") or mydie("Couldn't open $infile for reading.");;
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
    unlink $infile;
  }
  close LOG;
}

sub append_to_log { #filename ..., logfile
  my $logfile= pop @_;
  open(LOG, ">>$logfile") or mydie("Couldn't open $logfile for appending.");
  foreach my $infile (@_) {
    open(TMP, "<$infile")  or mydie("Couldn't open $infile for reading.");
    while(my $l = <TMP>) {
      print LOG $l;
    }
    close TMP;
  }
  close LOG;
}

sub move_to_err { #filename ..., logfile
  foreach my $infile (@_) {
    open(ERR, "<$infile");  ## We currently can't guarantee existence of $infile # or mydie("Couldn't open $infile for appending.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
    unlink $infile;
  }
}

# This functions filters output from LLVM's --time-passes
# into the time log. The source log file is modified to not
# contain this output as well.
sub filter_llvm_time_passes {
  my ($logfile) = @_;

  if ($time_passes) {
    open (my $L, '<', $logfile) or mydie("Couldn't open $logfile for reading.");
    my @lines = <$L>;
    close ($L);

    # Look for the specific output pattern that corresponds to the
    # LLVM --time-passes report.
    for (my $i = 0; $i <= $#lines;) {
      my $l = $lines[$i];
      if ($l =~ m/^\s+\.\.\. Pass execution timing report \.\.\.\s+$/) {
        # We are in a --time-passes section.
        my $start_line = $i - 1; # -1 because there's a ===----=== line before that's part of the --time-passes output

        # The end of the section is the SECOND blank line.
        for(my $j = 0; $j < 2; ++$j) {
          for(++$i; $i <= $#lines && $lines[$i] !~ m/^$/; ++$i) {
          }
        }
        my $end_line = $i;

        my @time_passes = splice (@lines, $start_line, $end_line - $start_line + 1);
        print $time_log join ("", @time_passes);

        # Continue processing the rest of the lines, taking into account that
        # a chunk of the array just got removed.
        $i = $start_line;
      }
      else {
        ++$i;
      }
    }

    # Now rewrite the log file without the --time-passes output.
    open ($L, '>', $logfile) or mydie("Couldn't open $logfile for writing.");
    print $L join ("", @lines);
    close ($L);
  }
}

# This is called between system call and check child error so it can 
# NOT do system calls
sub move_to_err_and_log { #String filename ..., logfile
  my $string = shift @_;
  my $logfile = pop @_;
  foreach my $infile (@_) {
    open ERR, "<$infile"  or mydie("Couldn't open $logfile for reading.");
    while(my $l = <ERR>) {
      print STDERR $l;
    }
    close ERR;
    move_to_log($string, $infile, $logfile);
  }
}

# Functions to execute external commands, with various wrapper capabilities:
#   1. Logging
#   2. Time measurement
# Arguments:
#   @_[0] = { 
#       'stdout' => 'filename',   # optional
#       'stderr' => 'filename',   # optional
#       'time' => 0|1,            # optional
#       'time-label' => 'string'  # optional
#     }
#   @_[1..$#@_] = arguments of command to execute
sub mysystem_full($@) {
  my $opts = shift(@_);
  my @cmd = @_;

  my $out = $opts->{'stdout'};
  my $err = $opts->{'stderr'};

  if ($verbose >= 2) {
    print join(' ',@cmd)."\n";
  }

  # Replace STDOUT/STDERR as requested.
  # Save the original handles.
  if($out) {
    open(OLD_STDOUT, ">&STDOUT") or mydie "Couldn't open STDOUT: $!";
    open(STDOUT, ">$out") or mydie "Couldn't redirect STDOUT to $out: $!";
    $| = 1;
  }
  if($err) {
    open(OLD_STDERR, ">&STDERR") or mydie "Couldn't open STDERR: $!";
    open(STDERR, ">$err") or mydie "Couldn't redirect STDERR to $err: $!";
    select(STDERR);
    $| = 1;
    select(STDOUT);
  }

  # Run the command.
  my $start_time = time();
  system(@cmd);
  my $end_time = time();

  # Restore STDOUT/STDERR if they were replaced.
  if($out) {
    close(STDOUT) or mydie "Couldn't close STDOUT: $!";
    open(STDOUT, ">&OLD_STDOUT") or mydie "Couldn't reopen STDOUT: $!";
  }
  if($err) {
    close(STDERR) or mydie "Couldn't close STDERR: $!";
    open(STDERR, ">&OLD_STDERR") or mydie "Couldn't reopen STDERR: $!";
  }

  # Dump out time taken if we're tracking time.
  if ($time_log && $opts->{'time'}) {
    my $time_label = $opts->{'time-label'};
    if (!$time_label) {
      # Just use the command as the label.
      $time_label = join(' ',@cmd);
    }

    log_time ($time_label, $end_time - $start_time);
  }
  return $?
}

sub mysystem_redirect($@) {
  # Run command, but redirect standard output to $outfile.
  my ($outfile,@cmd) = @_;
  return mysystem_full ({'stdout' => $outfile}, @cmd);
}

sub mysystem(@) {
  return mysystem_redirect('',@_);
}

sub hard_routing_error_code($@)
{
  my $error_string = shift @_;
  if( $error_string =~ /^Error \(170113\)/ ) {
    return 1;
  }
  return 0;
}

sub hard_routing_error($@)
 { #filename
     my $infile = shift @_;
     open(ERR, "<$infile");  ## if there is no $infile, we just return 0;
     while( <ERR> ) {
       if( hard_routing_error_code( $_ ) ) {
         return 1;
       }
     }
     close ERR;
     return 0;
 }

sub print_bsp_msgs($@)
 { 
     my $infile = shift @_;
     open(IN, "<$infile") or mydie("Failed to open $infile");
     while( <IN> ) {
       # E.g. Error: BSP_MSG: This is an error message from the BSP
       if( $_ =~ /BSP_MSG:/ ){
         my $filtered_line = $_;
         $filtered_line =~ s/BSP_MSG: *//g;
         if( $filtered_line =~ /^ *Error/ ) {
           print STDERR "$filtered_line";
         } elsif ( $filtered_line =~ /^ *Critical Warning/ ) {
           print STDOUT "$filtered_line";
         } elsif ( $filtered_line =~ /^ *Warning/ && $verbose > 0) {
           print STDOUT "$filtered_line";
         } elsif ( $verbose > 1) {
           print STDOUT "$filtered_line";
         }
       }
     }
     close IN;
 }

sub print_quartus_errors($@)
{ #filename
  my $infile = shift @_;
  my $flag_recomendation = shift @_;
  open(ERR, "<$infile");  ## if there is no $infile, we just die on the error
  while( <ERR> ) {
    if( $_ =~ /^Error/ ){
      if( hard_routing_error_code( $_ ) && $flag_recomendation ) {
        print STDERR "Error: Kernel fit error, recommend using --high-effort.\n";
      }
      if( $_ =~ /^Error \(11802\)/ ) {
        mydie("Cannot fit kernel(s) on device");
      }
    }
  }
  close ERR;
  mydie("Compiler Error, not able to generate hardware\n");
}

sub log_time($$) {
  my ($label, $time) = @_;
  if ($time_log) {
    printf ($time_log "[time] %s ran in %ds\n", $label, $time);
  }
}

sub save_pkg_section($$$) {
   my ($pkg,$section,$value) = @_;
   # The temporary file should be in the compiler work directory.
   # The work directory has already been created.
   my $file = $work_dir.'/value.txt';
   open(VALUE,">$file") or mydie("Can't write to $file: $!");
   binmode(VALUE);
   print VALUE $value;
   close VALUE;
   $pkg->set_file($section,$file)
       or mydie("Can't save value into package file: $acl::Pkg::error\n");
   unlink $file;
}

sub save_vfabric_files_to_pkg($$$$$) {
  my ($pkg, $var_id, $vfab_lib_path, $work_dir, $board_variant) = @_;
  if (!-f $vfab_lib_path."/var".$var_id.".fpga.bin" ) {
    mydie("Cannot find Rapid Prototyping programming file.");
  }

  if (!-f $vfab_lib_path."/sys_description.txt" ) {
    mydie("Cannot find Rapid Prototyping system description.");
  }

  if (!-f $work_dir."/vfabric_settings.bin" ) {
    mydie("Cannot find Rapid Prototyping configuration settings.");
  }

  # add the complete vfabric configuration file to the package
  $pkg->set_file('.acl.vfabric', $work_dir."/vfabric_settings.bin")
      or mydie("Can't save Rapid Prototyping configuration file into package file: $acl::Pkg::error\n");

  $pkg->set_file('.acl.fpga.bin', $vfab_lib_path."/var".$var_id.".fpga.bin" )
      or mydie("Can't save FPGA programming file into package file: $acl::Pkg::error\n");

  #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
  if( (-s $vfab_lib_path."/sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
    mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
  }
  $pkg->set_file('.acl.autodiscovery', $vfab_lib_path."/sys_description.txt")
      or mydie("Can't save system description into package file: $acl::Pkg::error\n");

  # Include the acl_quartus_report.txt file if it exists
  my $acl_quartus_report = $vfab_lib_path."/var".$var_id.".acl_quartus_report.txt";
  if ( -f $acl_quartus_report ) {
    $pkg->set_file('.acl.quartus_report',$acl_quartus_report)
       or mydie("Can't save Quartus report file $acl_quartus_report into package file: $acl::Pkg::error\n");
  }      
}

sub save_profiling_xml($$) {
  my ($pkg,$basename) = @_;
  # Save the profile XML file in the aocx
  $pkg->add_file('.acl.profiler.xml',"$basename.bc.profiler.xml")
      or mydie("Can't save profiler XML $basename.bc.profiler.xml into package file: $acl::Pkg::error\n");
}

# Make sure the board specification file exists. Return directory of board_spec.xml
sub find_board_spec {
  my ($acl_board_hw_path) = @_;
  my ($board_spec_xml) = acl::File::simple_glob( $acl_board_hw_path."/board_spec.xml" );
  my $xml_error_msg = "Cannot find Board specification!\n*** No board specification (*.xml) file inside ".$acl_board_hw_path.". ***\n" ;
  if ( $device_spec ne "" ) {
    my $full_path =  acl::File::abs_path( $device_spec );
    $board_spec_xml = $full_path;
    $xml_error_msg = "Cannot find Device Specification!\n*** device file ".$board_spec_xml." not found.***\n";
  }
  -f $board_spec_xml or mydie( $xml_error_msg );
  return $board_spec_xml;
}

# Do setup checks:
sub check_env {
  my ($board_variant) = @_;
  # 1. Is clang on the path?
  mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-clang$exesuffix) can not be found")  unless -x $clang_exe.$exesuffix; 
  # Do we have a license?
  my $clang_output = `$clang_exe --version 2>&1`;
  chomp $clang_output;
  if ($clang_output =~ /Could not acquire OpenCL SDK license/ ) {
    mydie("$prog: Can't find a valid license for the Intel(R) FPGA SDK for OpenCL(TM)\n");
  }
  if ($clang_output !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
    my $failure_cause = "The cause of failure cannot be determined. Run executable manually and watch for error messages.\n";
    # Common cause on linux is an old libstdc++ library. Check for this here.
    if ($^O !~ m/MSWin/) {
	    my $clang_err_out = `$clang_exe 2>&1 >/dev/null`;
	    if ($clang_err_out =~ m!GLIBCXX_!) {
	      $failure_cause = "Cause: Available libstdc++ library is too old. You're probably using an unsupported version of Linux OS. " .
	                       "A quick work-around for this is to get latest version of gcc (at least 4.4) and do:\n" .
	                       "  export LD_LIBRARY_PATH=<gcc_path>/lib64:\$LD_LIBRARY_PATH\n";
	    }
    }
    mydie("$prog: Executable $clang_exe exists but is not working!\n\n$failure_cause");
  }

  # 2. Is /opt/llc/system_integrator on the path?
  mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-opt$exesuffix) can not be found")  unless -x $opt_exe.$exesuffix;
  my $opt_out = `$opt_exe  --version 2>&1`;
  chomp $opt_out; 
  if ($opt_out !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
    mydie("$prog: Can't find a working version of executable (aocl-opt$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
  }
  mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (aocl-llc$exesuffix) can not be found")  unless -x $llc_exe.$exesuffix; 
  my $llc_out = `$llc_exe --version`;
  chomp $llc_out; 
  if ($llc_out !~ /Intel\(R\) FPGA SDK for OpenCL\(TM\), Version/ ) {
    mydie("$prog: Can't find a working version of executable (aocl-llc$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
  }
  mydie ("$prog: The Intel(R) FPGA SDK for OpenCL(TM) compiler front end (system_intgrator$exesuffix) can not be found")  unless -x $sysinteg_exe.$exesuffix; 
  my $system_integ = `$sysinteg_exe --help`;
  chomp $system_integ;
  if ($system_integ !~ /system_integrator - Create complete OpenCL system with kernels and a target board/ ) {
    mydie("$prog: Can't find a working version of executable (system_integrator$exesuffix) for the Intel(R) FPGA SDK for OpenCL(TM)\n");
  }

  # 3. Is Quartus on the path?
  $ENV{QUARTUS_OPENCL_SDK}=1; #Tell Quartus that we are OpenCL
  my $q_out = `quartus_sh --version`;
  $QUARTUS_VERSION = $q_out;

  chomp $q_out;
  if ($q_out eq "") {
    print STDERR "$prog: Quartus is not on the path!\n";
    print STDERR "$prog: Is it installed on your system and quartus bin directory added to PATH environment variable?\n";
    exit 1;
  }

  # 4. Is it right Quartus version?
  my $q_ok = 0;
  my $q_version = "";
  my $q_pro = 0;
  my $is_prime = 0;
  my $req_qversion_str = exists($ENV{ACL_ACDS_VERSION_OVERRIDE}) ? $ENV{ACL_ACDS_VERSION_OVERRIDE} : "16.1.0";
  my $req_qversion = acl::Env::get_quartus_version($req_qversion_str);

  foreach my $line (split ('\n', $q_out)) {
#    if ($line =~ /64-Bit/) {
#      $q_ok += 1;
#    }
    # With QXP flow should be compatible with future versions

    # Do version check.
    my ($qversion_str) = ($line =~ m/Version (\S+)/);
    my $qversion = acl::Env::get_quartus_version($qversion_str);
    if(acl::Env::are_quartus_versions_compatible($req_qversion, $qversion)) {
      $q_ok++;
    }
    
    # Need this to bypass version check for internal testing with ACDS 15.0.
    if ($line =~ /Prime/) {
      $is_prime++;
    }
    if ($line =~ /Pro Edition/) {
      $q_pro++;
    }
  }
  if ($q_ok != 1) {
    print STDERR "$prog: This release of the Intel(R) FPGA SDK for OpenCL(TM) requires ACDS Version $req_qversion_str (64-bit).";
    print STDERR " However, the following version was found: \n$q_out\n";
    exit 1;
  }
  
  # 5. Is it Quartus Prime Standard or Pro device?
  my $platform_type = undef;
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  $platform_type = acl::Env::aocl_boardspec( "$board_spec_xml", "automigrate_type");
  
  if (($is_prime == 1) && ($q_pro != 1) && ($platform_type =~ /^a10/)) {
    print STDERR "$prog: This release of Intel(R) FPGA SDK for OpenCL(TM) on A10 requires Quartus Prime Pro Edition.";
    print STDERR " However, the following version was found: \n$q_out\n";
    exit 1;
  }
  if (($is_prime == 1) && ($q_pro == 1) && ($platform_type !~ /^a10/)) {
    print STDERR "$prog: Use Quartus Prime Standard Edition for non A10 devices.";
    print STDERR " Current Quartus Version is: \n$q_out\n";
    exit 1;
  }
  
  # If here, everything checks out fine.
  print "$prog: Environment checks are completed successfully.\n" if $verbose;
  return;
}


sub extract_atoms_from_postfit_netlist($$$) {
  my ($base,$location,$atom) = @_;

   # Grab DSP location constraints from specified Quartus compile directory  
    my $script_abs_path = acl::File::abs_path( acl::Env::sdk_root()."/ip/board/bsp/extract_atom_locations_from_postfit_netlist.tcl"); 

    # Pre-process relativ or absolute location
    my $location_dir = '';
    if (substr($location,0,1) eq '/') {
      # Path is already absolute
      $location_dir = $location;
    } else {
      # Path is currently relative
      $location_dir = acl::File::abs_path("../$location");
    }
      
    # Error out if reference compile directory not found
    if (! -d $location_dir) {
      mydie("Directory '$location' for $atom locations does not exist!\n");
    }

    # Error out if reference compile board target does not match
    my $current_board = ::acl::Env::aocl_boardspec( ".", "name");
    my $reference_board = ::acl::Env::aocl_boardspec( $location_dir, "name");
    if ($current_board ne $reference_board) {
      mydie("Reference compile board name '$reference_board' and current compile board name '$current_board' do not match!\n");
    };

    my $project = ::acl::Env::aocl_boardspec( ".", "project");
    my $revision = ::acl::Env::aocl_boardspec( ".", "revision");
    chomp $revision;
    if (defined $ENV{ACL_QSH_REVISION})
    {
      # Environment variable ACL_QSH_REVISION can be used
      # replace default revision (internal use only).  
      $revision = $ENV{ACL_QSH_REVISION};
    }
    my $current_compile = acl::File::mybasename($location);
    my $cmd = "cd $location_dir;quartus_cdb -t $script_abs_path $atom $current_compile $base $project $revision;cd $work_dir";
    print "$prog: Extracting $atom locations from '$location' compile directory (from '$revision' revision)\n";
    my $locationoutput_full = `$cmd`;

    # Error out if project cannot be opened   
    (my $locationoutput_projecterror) = $locationoutput_full =~ /(Error\: ERROR\: Project does not exist.*)/s;
    if ($locationoutput_projecterror) {
      mydie("Project '$project' and revision '$revision' in directory '$location' does not exist!\n");
    }
 
    # Error out if atom netlist cannot be read
    (my $locationoutput_netlisterror) = $locationoutput_full =~ /(Error\: ERROR\: Cannot read atom netlist.*)/s;
    if ($locationoutput_netlisterror) {
      mydie("Cannot read atom netlist from revision '$revision' in directory '$location'!\n");
    }

    # Add location constraints to current Quartus compile directory
    (my $locationoutput) = $locationoutput_full =~ /(\# $atom locations.*)\# $atom locations END/s;
    my @designs = acl::File::simple_glob( "*.qsf" );
    $#designs > -1 or mydie ("Internal Compiler Error. $atom location argument was passed but could not find any qsf files\n");
    foreach (@designs) {
      my $qsf = $_;
      open(my $fd, ">>$qsf");
      print $fd "\n";
      print $fd $locationoutput;
      close($fd);
    }
}


sub get_acl_board_hw_path {
  my $bv = shift @_;
  my ($result) = acl::Env::board_hw_path($bv);
  return $result;
}


sub remove_named_files {
    foreach my $fname (@_) {
      acl::File::remove_tree( $fname, { verbose => ($verbose == 1 ? 0 : $verbose), dry_run => 0 } )
         or mydie("Cannot remove intermediate files under directory $fname: $acl::File::error\n");
    }
}

sub remove_intermediate_files($$) {
   my ($dir,$exceptfile) = @_;
   my $thedir = "$dir/.";
   my $thisdir = "$dir/..";
   my %is_exception = (
      $exceptfile => 1,
      "$dir/." => 1,
      "$dir/.." => 1,
   );
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      if ( $is_exception{$file} ) {
         next;
      }
      if ( $file =~ m/\.aclx$/ ) {
         next if $exceptfile eq acl::File::abs_path($file);
      }
      acl::File::remove_tree( $file, { verbose => $verbose, dry_run => 0 } )
         or mydie("Cannot remove intermediate files under directory $dir: $acl::File::error\n");
   }
   # If output file is outside the intermediate dir, then can remove the intermediate dir
   my $files_remain = 0;
   foreach my $file ( acl::File::simple_glob( "$dir/*", { all => 1 } ) ) {
      next if $file eq "$dir/.";
      next if $file eq "$dir/..";
      $files_remain = 1;
      last;
   }
   unless ( $files_remain ) { rmdir $dir; }
}

sub get_area_percent_estimates {
  # Get utilization numbers (in percent) from area.json.
  # The file must exist when this function is called.

  open my $area_json, '<', $work_dir."/area.json";
  my $util = 0;
  my $les = 0;
  my $ffs = 0;
  my $rams = 0;
  my $dsps = 0;

  while (my $json_line = <$area_json>) {
    if ($json_line =~ m/\[([.\d]+), ([.\d]+), ([.\d]+), ([.\d]+), ([.\d]+)\]/) {
      # Round all percentage values to the nearest whole number.
      $util = int($1 + 0.5);
      $les = int($2 + 0.5);
      $ffs = int($3 + 0.5);
      $rams = int($4 + 0.5);
      $dsps = int($5 + 0.5);
      last;
    }
  }
  close $area_json;

  return ($util, $les, $ffs, $rams, $dsps);
}

sub create_reporting_tool {
  my $filelist = shift;
  local $/ = undef;

  acl::File::make_path("$work_dir/reports") or mydie("Can't create Report directory: $!");

  acl::File::copy_tree(acl::Env::sdk_root()."/share/lib/acl_report/lib", "$work_dir/reports");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/Report.htm", "$work_dir/reports/report.html");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/main.js", "$work_dir/reports/lib/main.js");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/main.css", "$work_dir/reports/lib/main.css");
  acl::File::copy(acl::Env::sdk_root()."/share/lib/acl_report/spv/graph.js", "$work_dir/reports/lib/graph.js");

  open (my $report, ">$work_dir/reports/lib/report_data.js") or mydie("Could not open file report_data.js $!");

  open (my $area, '<', 'area.json') or mydie("Could not open file area.json $!");
  my $areaJSON = <$area>;
  close($area);

  open (my $mav, '<', 'mav.json') or mydie("Could not open file mav.json $!");
  my $mavJSON = <$mav>;
  close($mav);  

  open (my $loops, '<', 'loops.json') or mydie("Could not open file loops.json $!");
  my $loopsJSON = <$loops>;
  close($loops);  

  print $report "var loopsJSON=";   
  print $report $loopsJSON.";";

  print $report "var mavJSON=";
  print $report $mavJSON.";";
  
  print $report "var areaJSON=";   
  print $report $areaJSON.";";

  print $report "var fileJSON=";
  my $count = 0;
  my $filepath = "";
  my $filename = "";
  my @fileJSON;
  my @tempfilepath;

  foreach my $filein ( split(/\n/, $filelist) ) {
    if ($filein =~ m/\<unknown\>$/) {
      next;
    }

    if ($count) { 
      print $report ", {";
    } else {
      print $report "[{";
    }

    print $report '"index":'.$count;
    print $report ', "path":"'.$filein.'"';

    @tempfilepath = (split /\//, $filein);
    $filename = pop @tempfilepath;
    print $report ', "name":"'.$filename.'"';

    if ( -e $filein) {
      open (my $fin, '<', "$filein") or die "Could not open file $!";
      my $filecontent = <$fin>;
      close($fin);

      # $filecontent needs to be escaped since this in an input string which may have
      # quotes, and special characters. These can lead to invalid javascript which will
      # break the reporting tool.
      # The input from loops.json, area.json and mav.json is already valid JSON
      $filecontent =~ s/(\\(?!n))|(\\(?!t))|(\\(?!f))|(\\(?!b))|(\\(?!r))|(\\(?!"))/\\\\/g;
      $filecontent =~ s/(\012|\015\012|\015\015\012?)/\\012/g;
      $filecontent =~ s/(?<!\\)\\n/\\\\n/g;
      $filecontent =~ s/(?<!\\)\\t/\\\\t/g;
      $filecontent =~ s/(?<!\\)\\f/\\\\f/g;
      $filecontent =~ s/(?<!\\)\\b/\\\\b/g;
      $filecontent =~ s/(?<!\\)\\r/\\\\r/g;
      $filecontent =~ s/\"/\\"/g;
      print $report ', "content":"'.$filecontent.'"}';
    } else {
      print $report ', "content":""}';
    }

    $count = $count + 1;
  }
  print $report "];";
  close($report);
}

sub create_system {
  my ($base,$work_dir,$src,$obj,$board_variant, $using_default_board,$all_aoc_args) = @_;

  my $pkg_file_final = $obj;
  $pkg_file = $pkg_file_final.".tmp";
  $fulllog = "$base.log"; #definition moved to global space
  my $run_copy_skel = 1;
  my $run_copy_ip = 1;
  my $run_clang = 1;
  my $run_opt = 1;
  my $run_verilog_gen = 1;
  my $run_opt_vfabric = 0;
  my $run_vfabric_cfg_gen = 0;
  my $files;

  my $finalize = sub {
     unlink( $pkg_file_final ) if -f $pkg_file_final;
     rename( $pkg_file, $pkg_file_final )
         or mydie("Can't rename $pkg_file to $pkg_file_final: $!");
     chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");
  };

  if ( $parse_only || $opt_only || $verilog_gen_only || ($vfabric_flow && !$generate_vfabric) || $emulator_flow ) {
    $run_copy_ip = 0;
    $run_copy_skel = 0;
  }

  if ( $accel_gen_flow ) {
    $run_copy_skel = 0;
  }

  if ($vfabric_flow) {
    $run_opt = 0;
    $run_opt_vfabric = 1;
    $run_vfabric_cfg_gen = 1;
  }

  my $stage1_start_time = time();
  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $work_dir;
  # Cleaning up the whole project directory to avoid conflict with previous compiles. This behaviour should change for incremental compilation.
  if (-e $work_dir and -d $work_dir) {
    print "$prog: Cleaning up existing temporary directory $work_dir\n" if ($verbose >= 2);
  }
  foreach my $file ( acl::File::simple_glob( "$work_dir/*", { all => 1 } ) ) {
    if ( $file eq "$work_dir/." or $file eq "$work_dir/.." ) {
      next;
    }
    acl::File::remove_tree( $file )
      or mydie("Cannot remove files under temporary directory $work_dir: $!\n");
  }
  acl::File::make_path($work_dir) or mydie("Can't create temporary directory $work_dir: $!");
  # First, try to delete the log file
  if (!unlink "$work_dir/$fulllog") {
    # If that fails, just try to erase the existing log
    open(LOG, ">$work_dir/$fulllog") or mydie("Couldn't open $work_dir/$fulllog for writing.");
    close(LOG);
  }
  open(my $TMPOUT, ">$work_dir/$fulllog") or mydie ("Couldn't open $work_dir/$fulllog to log version information.");
  print $TMPOUT "Compiler Command: " . $prog . " " . $all_aoc_args . "\n";
  if ($regtest_mode){
      version ($TMPOUT);
  }
  close($TMPOUT);
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);

  # If just packaging an HDL library component, call 'aocl library' and be done with it.
  if ($hdl_comp_pkg_flow) {
    print "$prog: Packaging HDL component for library inclusion\n" if $verbose||$report;
    $return_status = mysystem_full(
        {'stdout' => "$work_dir/aocl_libedit.log", 
         'stderr' => "$work_dir/aocl_libedit.err",
         'time' => 1, 'time-label' => 'aocl library'},
        "$aocl_libedit_exe -c \"$absolute_srcfile\" -o \"$output_file\"");
    move_to_log("!========== [aocl library] ==========", "$work_dir/aocl_libedit.log", "$work_dir/$fulllog"); 
    append_to_log("$work_dir/aocl_libedit.err", "$work_dir/$fulllog");
    move_to_err("$work_dir/aocl_libedit.err");
    $return_status == 0 or mydie("Packing of HDL component FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    return $return_status;
  }
  
  # Make sure the board specification file exists. This is needed by multiple stages of the compile.
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  my $llvm_board_option = "-board $board_spec_xml";   # To be passed to LLVM executables.
  my $llvm_efi_option = (defined $absolute_efispec_file ? "-efi $absolute_efispec_file" : ""); # To be passed to LLVM executables
  my $llvm_profilerconf_option = (defined $absolute_profilerconf_file ? "-profile-config $absolute_profilerconf_file" : ""); # To be passed to LLVM executables
  my $llvm_library_option = ($#resolved_lib_files > -1 ? join (' -libfile ', (undef, @resolved_lib_files)) : "");
  
  if (!$accel_gen_flow && !$soft_ip_c_flow) {
    my $default_text;
    if ($using_default_board) {
       $default_text = "default ";
    } else {
       $default_text = "";
    }
    print "$prog: Selected ${default_text}target board $board_variant\n" if $verbose||$report;
  }

  if(defined $absolute_efispec_file) {
    print "$prog: Selected EFI spec $absolute_efispec_file\n" if $verbose||$report;
  }

  if(defined $absolute_profilerconf_file) {
    print "$prog: Selected profiler conf $absolute_profilerconf_file\n" if $verbose||$report;
  }

  if ( $run_copy_skel ) {
    # Copy board skeleton, unconditionally.
    # Later steps update .qsf and .sopc in place.
    # You *will* get SOPC generation failures because of double-add of same
    # interface unless you get a fresh .sopc here.
    acl::File::copy_tree( $acl_board_hw_path."/*", $work_dir )
      or mydie("Can't copy Board template files: $acl::File::error");
    map { acl::File::make_writable($_) } (
      acl::File::simple_glob( "$work_dir/*.qsf" ),
      acl::File::simple_glob( "$work_dir/*.sopc" ) );
  }

  if ( $run_copy_ip ) {
    # Rather than copy ip files from the SDK root to the kernel directory, 
    # generate an opencl.ipx file to point Qsys to hw.tcl components in 
    # the IP in the SDK root when generating the system.
    my $opencl_ipx = "$work_dir/opencl.ipx";
    open(my $fh, '>', $opencl_ipx) or die "Cannot open file '$opencl_ipx' $!";
    print $fh '<?xml version="1.0" encoding="UTF-8"?>
<library>
 <path path="${ALTERAOCLSDKROOT}/ip/*" />
</library>
';
    close $fh;

    # Also generate an assignment in the .qsf pointing to this IP.
    # We need to do this because not all the hdl files required by synthesis
    # are necessarily in the hw.tcl (i.e., not the entire file hierarchy).
    #
    # For example, if the Qsys system needs A.v to instantiate module A, then
    # A.v will be listed in the hw.tcl. Every file listed in the hw.tcl also
    # gets copied to system/synthesis/submodules and referenced in system.qip,
    # and system.qip is included in the .qsf, therefore synthesis will be able
    # to find the file A.v. 
    #
    # But if A instantiates module B, B.v does not need to be in the hw.tcl, 
    # since Qsys still is able to find B.v during system generation. So while
    # the Qsys generation will still succeed without B.v listed in the hw.tcl, 
    # B.v will not be copied to submodules/ and will not be included in the .qip,
    # so synthesis will fail while looking for this IP file. This happens in the 
    # virtual fabric flow, where the full hierarchy is not included in the hw.tcl.
    #
    # Since we are using an environment variable in the path, move the
    # assignment to a tcl file and source the file in each qsf (done below).
    my $ip_include = "$work_dir/ip_include.tcl";
    open($fh, '>', $ip_include) or die "Cannot open file '$ip_include' $!";
    print $fh 'set_global_assignment -name SEARCH_PATH "$::env(ALTERAOCLSDKROOT)/ip"
';
    close $fh;

    # Add SEARCH_PATH for ip/$base to the QSF file
    foreach my $qsf_file (acl::File::simple_glob( "$work_dir/*.qsf" )) {
      open (QSF_FILE, ">>$qsf_file") or die "Couldn't open $qsf_file for append!\n";

      # Source a tcl script which points the project to the IP directory
      print QSF_FILE "\nset_global_assignment -name SOURCE_TCL_SCRIPT_FILE ip_include.tcl\n";

      # Case:149478. Disable auto shift register inference for appropriately named nodes
      print "$prog: Adding wild-carded AUTO_SHIFT_REGISTER_RECOGNITION assignment to $qsf_file\n" if $verbose>1;
      print QSF_FILE "\nset_instance_assignment -name AUTO_SHIFT_REGISTER_RECOGNITION OFF -to *_NO_SHIFT_REG*\n";

      # allow for generate loops with bounds over 5000
      print QSF_FILE "\nset_global_assignment -name VERILOG_CONSTANT_LOOP_LIMIT 10000\n";

      close (QSF_FILE);
    }
  }

  my $optinfile = "$base.1.bc";
  my $pkg = undef;

  # Copy the CL file to subdir so that archived with the project
  # Useful when creating many design variants
  # But make sure it doesn't end with .cl
  acl::File::copy( $absolute_srcfile, $work_dir."/".acl::File::mybasename($absolute_srcfile).".orig" )
   or mydie("Can't copy cl file to destination directory: $acl::File::error");

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink "$objfile";

  if ( $soft_ip_c_flow ) {
      $clang_arg_after = "-x soft-ip-c -soft-ip-c-func-name=$soft_ip_c_name";
  } elsif ($accel_gen_flow ) {
      $clang_arg_after = "-x cl -soft-ip-c-func-name=$accel_name";
  }

  # Late environment check IFF we are using the emulator
  if (($emulator_arch eq 'windows64') && ($emulator_flow == 1) ) {
    my $msvc_out = `LINK 2>&1`;
    chomp $msvc_out; 

    if ($msvc_out !~ /Microsoft \(R\) Incremental Linker Version/ ) {
      mydie("$prog: Can't find VisualStudio linker LINK.EXE.\nEither use Visual Studio x64 Command Prompt or run %ALTERAOCLSDKROOT%\\init_opencl.bat to setup your environment.\n");
    }
  }

  if ( $run_clang ) {
    my $clangout = "$base.pre.bc";
    my @cmd_list = ();

    # Create package file in source directory, and save compile options.
    $pkg = create acl::Pkg($pkg_file);

    # Figure out the compiler triple for the current flow.
    my $fpga_triple = 'fpga64';
    my $emulator_triple = ($emulator_arch eq 'windows64') ? 'x86_64-pc-win32' : 'x86_64-unknown-linux-gnu';
    my $cur_flow_triple = $emulator_flow ? $emulator_triple : $fpga_triple;
    
    my @triple_list;
    
    # Triple list to compute.
    if ($created_shared_aoco) {
      @triple_list = ($fpga_triple, 'x86_64-pc-win32', 'x86_64-unknown-linux-gnu');
    } else {
      @triple_list = ($cur_flow_triple);
    }
    
    if ( not $c_acceleration ) {
      print "$prog: Running OpenCL parser....\n" if $verbose; 
      chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");

      # Emulated flows to cover
      my @emu_list = $created_shared_aoco ? (0, 1) : $emulator_flow;

      # These two nested loops should produce either one clang call for regular compiles
      # Or three clang calls for three triples if -shared was specified: 
      #     (non-emulated, fpga), (emulated, linux), (emulated, windows)
      foreach my $emu_flow (@emu_list) {        
        foreach my $cur_triple (@triple_list) {
        
          # Skip {emulated_flow, triple} combinations that don't make sense
          if ($emu_flow and ($cur_triple =~ /fpga/)) { next; }
          if (not $emu_flow and ($cur_triple !~ /fpga/)) { next; }
          
          my $cur_clangout;
          if ($cur_triple eq $cur_flow_triple) {
            $cur_clangout = "$work_dir/$base.pre.bc";
          } else {
            $cur_clangout = "$work_dir/$base.pre." . $cur_triple . ".bc";
          }

          my @debug_options = ( $debug ? qw(-mllvm -debug) : ());
          my @llvm_library_option = ( $emu_flow ? map { (qw(-mllvm -libfile -mllvm), $_) } @resolved_lib_files : ()); 
          my @clang_std_opts = ( $emu_flow ? qw(-cc1 -target-abi opencl -emit-llvm-bc -mllvm -gen-efi-tb -Wuninitialized) : qw( -cc1 -O3 -emit-llvm-bc -Wuninitialized));
          my @board_options = map { ('-mllvm', $_) } split( /\s+/, $llvm_board_option );
          my @board_def = (
              "-DACL_BOARD_$board_variant=1", # Keep this around for backward compatibility
              "-DAOCL_BOARD_$board_variant=1",
              );
          my @clang_arg_after_array = split(/\s+/m,$clang_arg_after);
          
          @cmd_list = (
              $clang_exe, 
              @clang_std_opts,
              ('-triple',$cur_triple),
              @board_options,
              @board_def,
              @debug_options, 
              $absolute_srcfile,
              @clang_arg_after_array,
              '-o',
              $cur_clangout,
              @user_clang_args,
              );
          $return_status = mysystem_full(
              {'stdout' => "$work_dir/clang.log",
               'stderr' => "$work_dir/clang.err",
               'time' => 1, 
               'time-label' => 'clang'},
              @cmd_list);
              
          # Only save warnings and errors corresponding to current flow triple.
          # Otherwise, will get all warnings in triplicate.
          if ($cur_triple eq $cur_flow_triple) {
            move_to_log("!========== [clang] parse ==========", "$work_dir/clang.log", "$work_dir/$fulllog"); 
            append_to_log("$work_dir/clang.err", "$work_dir/$fulllog");
            move_to_err("$work_dir/clang.err");
          }
          $return_status == 0 or mydie("OpenCL parser FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
          
          # Save clang output to .aoco file. This will be used for creating
          # a library out of this file.
          # ".acl.clang_ir" section prefix name is also hard-coded into lib/libedit/inc/libedit.h!
          $pkg->set_file(".acl.clang_ir.$cur_triple", $cur_clangout)
               or mydie("Can't save compiler object file $cur_clangout into package file: $acl::Pkg::error\n");
        }
      }
    }

    if ( $parse_only ) { 
      unlink $pkg_file;
      return;
    }

    if ( defined $program_hash ){ 
      save_pkg_section($pkg,'.acl.hash',$program_hash);
    }
    if ($emulator_flow) {
      save_pkg_section($pkg,'.acl.board',$emulatorDevice);
    } else {
      save_pkg_section($pkg,'.acl.board',$board_variant);
    }
    save_pkg_section($pkg,'.acl.compileoptions',join(' ',@user_opencl_args));
    # Set version of the compiler, for informational use.
    # It will be set again when we actually produce executable contents.
    save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());
    
    print "$prog: OpenCL parser completed successfully.\n" if $verbose;
    if ( $disassemble ) { mysystem("llvm-dis \"$work_dir/$clangout\" -o \"$work_dir/$clangout.ll\"" ) == 0 or mydie("Cannot disassemble: \"$work_dir/$clangout\"\n"); }

    if ( $pkg_save_extra || $profile || $dash_g ) {
      $files = `file-list \"$work_dir/$clangout\"`;
      my $index = 0;
      foreach my $file ( split(/\n/, $files) ) {
         # "Unknown" files are included when opaque objects (such as image objects) are in the source code
         if ($file =~ m/\<unknown\>$/) {
            next;
         }
        save_pkg_section($pkg,'.acl.file.'.$index,$file);
        $pkg->add_file('.acl.source.'. $index,$file)
        or mydie("Can't save source into package file: $acl::Pkg::error\n");
        $index = $index + 1;
      }
      save_pkg_section($pkg,'.acl.nfiles',$index);

      $pkg->add_file('.acl.source',$absolute_srcfile)
      or mydie("Can't save source into package file: $acl::Pkg::error\n");
    }


    # For emulator and non-emulator flows, extract clang-ir for library components
    # that were written using OpenCL
    if ($#resolved_lib_files > -1) {
      foreach my $libfile (@resolved_lib_files) {
        if ($verbose >= 2) { print "Executing: $aocl_libedit_exe extract_clang_ir \"$libfile\" $cur_flow_triple $work_dir\n"; }
        my $new_files = `$aocl_libedit_exe extract_clang_ir \"$libfile\" $cur_flow_triple $work_dir`;
        if ($? == 0) {
          if ($verbose >= 2) { print "  Output: $new_files\n"; }
          push @lib_bc_files, split /\n/, $new_files;
        }
      }
    }
    
    # do not enter to the work directory before this point, 
    # $pkg->add_file above may be called for files with relative paths
    chdir $work_dir or mydie("Can't change dir into $work_dir: $!");

    if ($emulator_flow) {
      print "$prog: Compiling for Emulation ....\n" if $verbose;
      # Link with standard library.
      my $emulator_lib = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_emulation.bc");
      @cmd_list = (
          $link_exe,
          "$work_dir/$clangout",
          @lib_bc_files,
          $emulator_lib,
          '-o',
          $optinfile );
      $return_status = mysystem_full(
          {'stdout' => "$work_dir/clang-link.log", 
           'stderr' => "$work_dir/clang-link.err",
           'time' => 1, 'time-label' => 'link (early)'},
          @cmd_list);
      move_to_log("!========== [link] early link ==========", "$work_dir/clang-link.log",
		  "$work_dir/$fulllog");
      move_to_err("$work_dir/clang-link.err");
      remove_named_files($clangout) unless $save_temps;
      foreach my $lib_bc_file (@lib_bc_files) {
        remove_named_files($lib_bc_file) unless $save_temps;
      }
      $return_status == 0 or mydie("OpenCL parser FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      my $debug_option = ( $debug ? '-debug' : '');
      my $emulator_efi_option = ( $#resolved_lib_files > -1 ? '-createemulatorefiwrappers' : '');
      $return_status = mysystem_full(
	        {'time' => 1, 
	         'time-label' => 'opt (opt (emulator tweaks))'},
	        "$opt_exe -translate-library-calls -reverse-library-translation -lowerconv -scalarize -scalarize-dont-touch-mem-ops -insert-ip-library-calls -createemulatorwrapper $emulator_efi_option -generateemulatorsysdesc  $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option $opt_arg_after \"$optinfile\" -o \"$base.bc\" >>$fulllog 2>opt.err" );
      filter_llvm_time_passes("opt.err");
      move_to_err_and_log("========== [aocl-opt] Emulator specific messages ==========", "opt.err", $fulllog);
      $return_status == 0 or mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

      $pkg->set_file('.acl.llvmir',"$base.bc")
          or mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");

      #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
      my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
      if( (-s "sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
        mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
      }
      $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
          or mydie("Can't save system description into package file: $acl::Pkg::error\n");

      my $arch_options = ();
      if ($emulator_arch eq 'windows64') {
        $arch_options = "-cc1 -triple x86_64-pc-win32 -emit-obj -o libkernel.obj";
      } else {
        $arch_options = "-fPIC -shared -Wl,-soname,libkernel.so -L\"$ENV{\"ALTERAOCLSDKROOT\"}/host/linux64/lib/\" -lacl_emulator_kernel_rt -o libkernel.so";
      }
      $return_status = mysystem_full(
          {'time' => 1, 
           'time-label' => 'clang (executable emulator image)'},
          "$clang_exe $arch_options -O0 \"$base.bc\" >>$fulllog 2>opt.err" );
      filter_llvm_time_passes("opt.err");
      move_to_err_and_log("========== [clang compile kernel emulator] Emulator specific messages ==========", "opt.err", $fulllog);
      $return_status == 0 or mydie("Optimizer FAILED.\nRefer $base/$fulllog for details.\n");

      if ($emulator_arch eq 'windows64') {
        $return_status = mysystem_full(
            {'time' => 1, 
             'time-label' => 'clang (executable emulator image)'},
            "link /DLL /EXPORT:__kernel_desc,DATA /EXPORT:__channels_desc,DATA /libpath:$ENV{\"ALTERAOCLSDKROOT\"}\\host\\windows64\\lib acl_emulator_kernel_rt.lib msvcrt.lib libkernel.obj>>$fulllog 2>opt.err" );
        filter_llvm_time_passes("opt.err");
        move_to_err_and_log("========== [Create kernel loadbable module] Emulator specific messages ==========", "opt.err", $fulllog);
        $return_status == 0 or mydie("Linker FAILED.\nRefer $base/$fulllog for details.\n");
        $pkg->set_file('.acl.emulator_object.windows',"libkernel.dll")
            or mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      } else {     
        $pkg->set_file('.acl.emulator_object.linux',"libkernel.so")
          or mydie("Can't save emulated kernel into package file: $acl::Pkg::error\n");
      }

      if(-f "kernel_arg_info.xml") {
        $pkg->set_file('.acl.kernel_arg_info.xml',"kernel_arg_info.xml");
        unlink 'kernel_arg_info.xml' unless $save_temps;
      } else {
        print "Cannot find kernel arg info xml.\n" if $verbose;
      }

      my $compilation_env = compilation_env_string($work_dir,$board_variant,$all_aoc_args);
      save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

      # Compute runtime.
      my $stage1_end_time = time();
      log_time ("emulator compilation", $stage1_end_time - $stage1_start_time);

      print "$prog: Emulator Compilation completed successfully.\n" if $verbose;
      &$finalize();
      return;
    } 

    # Link with standard library.
    my $early_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_early.bc");
    @cmd_list = (
        $link_exe,
        "$work_dir/$clangout",
        @lib_bc_files,
        $early_bc,
        '-o',
        $optinfile );
    $return_status = mysystem_full(
        {'stdout' => "$work_dir/clang-link.log", 
         'stderr' => "$work_dir/clang-link.err",
         'time' => 1, 
         'time-label' => 'link (early)'},
        @cmd_list);
    move_to_log("!========== [link] early link ==========", "$work_dir/clang-link.log",
        "$work_dir/$fulllog");
    move_to_err("$work_dir/clang-link.err");
    remove_named_files($clangout) unless $save_temps;
    foreach my $lib_bc_file (@lib_bc_files) {
      remove_named_files($lib_bc_file) unless $save_temps;
    }
    $return_status == 0 or mydie("OpenCL linker FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
  }

  chdir $work_dir or mydie("Can't change dir into $work_dir: $!");

  my $disabled_lmem_replication = 0;
  my $restart_acl = 1;  # Enable first iteration
  my $opt_passes = $dft_opt_passes;
  if ( $soft_ip_c_flow ) {
      $opt_passes = $soft_ip_opt_passes;
  }

  if ( $run_opt_vfabric ) {
    print "$prog: Compiling with Rapid Prototyping flow....\n" if $verbose;
    $restart_acl = 0;
    my $debug_option = ( $debug ? '-debug' : '');
    my $profile_option = ( $profile ? '-profile' : '');

    # run opt
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'opt ', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
        "$opt_exe --acle ljg7wvyc1geoldvzy1bknywbngf1qb17frkm0t0zbrebqj07ekh3nrwxc2f1qovp3xd38uui32qclkjpatdzqkpbcrk33czpyxjb0tjo1gu7qgwpk3h72tfxmrkmn3ppl2vs0rdovx713svzkhhfnedx1rzbtijzgggh0qyi720qqkwojhdonj0xcracmczpq2z3uhb7yv1c2y77ekh3njvc7ra1q8dolxfhwtfmireznrpokcdknw0318a7qxvp1rkb0uui3gleqgfpttd7mtvcura1q3ypdgg38uui32wmljwpekh3lqjxcrkbtijz32h37ujibglkmsjzy1bknyvbzga3loype2s7wywo880qqkvot3jfnupblgd3low7ljg7wu0o7x713svze3j1qq8v18a7mvjolxbbyw0oprl7lgpoekh3nt0vwgd7q3w7ljg7wrporgukqgpoy1bkny8xxxkcnvvpagkuwwdo880qqkvok3h7qq8x2gh7qxvzt8vs0ryoeglzmr8pshhmlhwblxk33czpy2km7yvzrrluqswokthkluu3xxf7nvyzs2kmegdoyxl13svz3tdmluu3xxfbmbdos2sbyw0o3ru1mju7atj3meyxwrauqxyiljg7wepi2rebmawp3cvorlvcigjkq187frkceq8z72e3qddpqcvorlvc7rjcl8ypu2dc7uvzrrlcljjzucfqnldx0jpsmvjzdgfm7uji1xy1mgy7atj7qjjxwgfzmb0ogrgswtfmirezldyp8chqlr8vm2dzqb17frkuww0zwreeqapzkhholuu3xxfcnbypsrk1weji7xlkqa07ekh3nj8xbrkhmzpzxrko0yvm7jlzmuyzutd3mlvczgfcncw7ljg7wewioxu13svz2thzmuwb1rzbtijzs2h70evm7jlzmajpscdorlvcu2a7n2ypmrkt0uui3xyhmuyz3cghlqwc18acq1e7ljg7wewioxu13svz7hh3mg8xyxftqb17frkuww0zwreeqapzkhholuu3xxfuqi0z72km7gvm7jlzmajpscdorlvczrdumi8pt8vs0rjiorlclgfptckolqycygsfqiw7ljg70yyzix713svzf3ksny0bfxa3l3w7ljg70g0o3xuctgfpt3gknjwbmxakqvypf2j38uui3gq1la0oekh3lh0xlgd1qcypfrj38uui3reemupoechmlhyc8gpsmvwo1rg37two1xykqsdpy1bknywcqgd33czpy2kc0rdo880qqkvok3h7qq8x2gh7qxvzt8vs0rpiiru3lkjpfhjqllyc0jpsmvjomgfuwhdmire3qg8zw3bkny0blxacni0oxxfb0gvm7jlzqhwpshjmlqwcmgd33czpyrkfww0zw2l1mujzecvorlvcngfml8yplgf38uui3reemsdoehdzmtfxmgsfq80zljg70qwiqgu13svz0thorlvcz2acl8ypfrfu0r0z880qqkwpsth7mtfxmxkumowos2ho0svm7jlzmavz3tdmluu3xxfhmivp32vs0rdziguemawpy1bknyvbzga3loype2s7wywo880qqkvottj7quu3xxfzq2ppt8vs0rdi72lzmy8iscdzquu3xxfuqijomrkf0e8obgl1mju7atjunhyxwgpsmv0ohgfb0tjobgl7mju7atj3nlpblgdhmb0olxjbyw0oyguemy8zq3jzmejxxrzbtijzqrfbwtfmirebmgvzecvorlvcqgskq10pggju7ryomx713svzkhh3qhvccgammzpplxbbyw0otxyold0oekh3ltyc7rdbtijz3gffwkwiw2tclgvoy1bknyjcvxammb0pqrkbwtfmirezqsdp3cfsntpb3gd33czpygk1wg8zb2wonju7atjmlqjb7gh7nczpy2hswepii2wctgfpthhhljyxlgdclb17frkc0yyze2wctgfpt3j3lqy3xxfhmiyzq2vs0r0zwrlolgy7atjqllwblgssm8ypyrfbyw0o1xw3mju7atjfnljb12k7mipp7xbbyw0o0re1mju7atjmlqjb7gh7nczpygfb0ewil2w13svzf3ksntfxmgssq3doggg77q0otx713svz23ksnldb1gpsmvvpdgkbyw0o1rezqgvo33k3quu3xxfcmv8zt8vs0r0z32etqjpo23k7qq0318a7qcjzlxbbyw0oeru1qgfptcd1medbl8kbmx87frkceq8z7ruhqswpwcvorlvcw2kuq2dm12jz0uui3xyhmuyz3cghlqwc18acm8fmt8vs0rvzr2qmnuzoetk72tfxm2kbmovp72jbyw0obglkmr8puchqld8cygsfqi87frk7ekwir2wznju7atj1mtyxc2jbmczpy2ds0jpoixy1mgy7atj3nuwxvxk33czpyxfm7wdioxy1mypokhf72tfxmgfcmv8zt8vs0rjiorlclgfpttdqnq0bvgsom7w7ljg7whvib20qqkvzs3jfntvbmgssmxw7ljg70gpizxutqddzbtjbnr0318a7mzpp8xd70wdi22qqqg07ekh3ltvc1rzbtijze2ht7kvz7jlzmk8p0tjmnjwbqrzbtijzs2g77uui32l1mujze3bkny8cvra33czpyxgk0udi7jlzqu0od3gzqhyclrzbtijz72jm7qyokx713svzath1mqwxqrzbtijzrxdcegpi22y3lg0o2th7mujc7rjumippt8vs0rwolglctgfptck3nt0318a7m8ypaxfh0qyokremqh07ekh3lqvby2kbnv0oggjuetfmirekmsvo0tjhnqpcz2abmczpyggf0uui3gyctgfpttd3nuwx72kuq08zljg7weporrw1qgfpt3jcnrpb1xd1q38z8xbbyw0otrebma8z2hdolkwx0jpsmv0zy2j38uui3gwkmwyo83bknypczrj7mbjomrf38uui3xleqtyz2tdcmewbmrs33czpyrf70tji1gukmeyzekh3ltjxxrjbtijzmrgb7rvi7jl3mrpo73k72tfxmxk7mb0prgfuwado880qqkwzt3k72tfxmgfcmv8zt8vs0rwolglctgfptck3nt0318a7mzpp8xd70wdi22qqqg07ekh3lkpbcxdmnb8pljg70yjiogebmay7atjsntyx0jpsmvwo1rgzwgpoz20qqkjzdth1nuwx18a7mo8za2vs0rdzt2e7qg07ekh3njvxzrkbtijz8xjuwjdmireznuyzf3bknyjxwrj33czpyxdm7qyzb2etqgfpt3hmlh0x0jpsmvypfxjbws0zq2ecny8patk72tfxmrjmnbpp8gjfwgdi7jlzmypokhhzqr0318a7qovpdxfbyw0ot2qumywpkhkqquu3xxfhmvjo82k38uui32l1majpscd72tfxm2jbq8ype2s38uui3xleqs0oekh3nj8xbrkhmzpzxxbbyw0oprezlu8zy1bknypcn2dmncyoljg70tyiirl3ljwoecvorlvcn2k1qijzh2vs0r0ooglmlgpo33ghllp10jpsmv0zy2j38uui32qqquwotthsly8xxgd33czpygdb0rjzogukmeyzekh3nwycl2abqow7ljg7wjdor2qmqw07ekh3nrdbxrzbtijzggg7ek0oo2loqddpecvorlvc8xfbqb17frko7u8zbgwknju7atj1mtyxc2jbmczpyxjb0tjo7jlzquwoshdonj0318a7qcjzlxbbyw0ol2wolddzbcvorlvcbgdmnx8zljg7wh8z7xwkqk8z03kzntfxmxkcnidolrf38uui3xwzqg07ekh3nedxqrj7mi8pu2hs0uvm7jlzqjwzt3k72tfxmraumv8pt8vs0rjiorlclgfpttjhnqpcz2abqb17frkh0q0ozx713svzn3k1medcfrzbtijzsrgfwhdmire3nu8p8tjhnhdxygpsmvyzfggfwkpow2wctgfpttj1lk0318a7q28z12ho0svm7jlzqddp3cf3nlyxngssmcw7ljg70yyzix713svz33gslkwxz2dunvpzwxbbyw0oz2wolhyz23kzmhpbxrzbtijz82hkwhjibgwklkdzqcvorlvcvxazncdo8rduwk0ovx713svzqhfkluu3xxfcl8yp72h1wedmireuqjwojcvorlvc8xfbqb17frk77ujz1xlkqhdpf3kklhvb0jpsmvpolgfuwypp880qqkpoeckomyyc18a7q88z8rgbeg0o7ructgfptck3nt0318a7q28z12ho0svm7jlzqjwzg3f3qhy3xxf7nzdilrf38uui3rukqa0od3gbnfvc2xd33czpyxgf0jdorru7ldwotcg72tfxm2f1q8dog2jm7gjzkxl1mju7atjznyyc0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpy2gb0edmireoqjdph3bkny0bc2kcnczpy2k77gpimgluqgdp0cvorlvcvxa7mb0pljg70edoz20qqkwpkhkolh8xbgd7nczpyxjfwwjz7jlzqkjpfcdoqhyc0jpsmv0p0rjh0qyit2wonr07ekh3nuwxtgfun887frkm7ujzeguqqgfptcgcmgjczrd33czpygfbwkviqry7qdwzy1bknydb2rk1mvjpgxj7etfmire7lddpy1bknyjbc2kemz0ol2gbyw0obgl3nu8patdqnyvb18a7qovp02jm7u8z880qqkdz7tdontfxmrjmnzvzdggf0edowgukqky7atjbnhdxmrjumipp8xbbyw0o0rl1nkwpe3bkny0buga3nczpygj37uui32yqqdwoy1bkny8xxxkcnvvpagkuwwdo880qqkwzt3k72tfxm2d3nv87frkc0u0oo2lclsvokcfqnldx0jpsmvypfrfc7rwizgekmsyzy1bknywcmgd33czpygj37rdmirezqsdpn3k1mj8xc2abtijz12jk0wyz1xlctgfpt3gknjwbmxakqvypf2j38uui3xwzqg07ekh3nrdbxrzbtijzaxfcwtfmireolgwz7tjontfxmrdbq18zfxjbww0o720qqkwzktdzmudxmgd33czpy2kmegpok20qqk0o23gbquu3xxf1qippdxd1wkdo7jlzqayzfckolk0318a7q10pdrg37uui3xukmyyzd3gknedx3gpsmvpoe2kmwgpi3x713svz8hdontfxmrafmiwoljg7whpiy2wtqddpkhhcluu3xxfmnc8pdgdb0uui3xw1nywpktjmlhyc18a7qcdzwxbbyw0omgyqmju7atjqllvbyxffmodzgggbwtfmirebmgvzecvorlvcqxfuq2w7ljg7wewioxu13svz83g7mtwxz2auqivzt8vs0rpiiru3lkjpfhjqllyc0jpsmv0zy2j38uui3gu1qajpn3korlvc8gj3loypy2kc7udmire3mkjzy1bknyvbzga3loype2s7wywo880qqkwpstfoljvbtgscnvwpt8vs0rjooxy13svzthkcntfxmrafmiwoljg7whpiy2wtqddpkhhcluu3xxf1qcdpnrfc7uui3rukmeyz3cvorlvcrgdmnzpzxxbbyw0ol2wolddzbcvorlvcmxasq28z1xdbyw0o7xt3lgfptcfhntfxmxkbqo8zyxd38uui3gy1qkwoshdqldyc18a7mzpp8xd7etfmire3qkyzy1bknyjcr2a33czpyxj70uvm7jlzqddp3cf3nlyxngssmcw7ljg7wu0o7x713svz23ksnuwb12kumb0pggsb0uui3gwemuy7atjbqr8cnrzbtijz12jk0tjz7gukqjwpkhaoluu3xxfcmv8zt8vs0rjzr2qmld8zd3bkny8xxxkcn887frko0w8z7jlzmtdzuhj72tfxmrjmnzpog2kh0uui32qqquwo23f3lh8xc2abtijz12j3eepi32e3ldjpacvorlvc1rh3nijol2vs0rjibgy1qgfpthfmlqyb1xk33czpyxj70uvmijn $llvm_board_option $debug_option $opt_arg_after \"$optinfile\" -o \"$base.bc\"" );
    filter_llvm_time_passes('opt.err');
    move_to_log("!========== [opt] ==========", 'opt.log', 'opt.err', $fulllog);
    move_to_err('opt.err'); # Warnings/errors
    if ($return_status != 0) {
      mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    }

    # Finish up opt-like steps.
    if ( $run_opt || $run_opt_vfabric ) {
      if ( $disassemble || $soft_ip_c_flow ) { mysystem("llvm-dis \"$base.bc\" -o \"$base.ll\"" ) == 0 or mydie("Cannot disassemble: \"$base.bc\"\n"); }
      if ( $pkg_save_extra ) {
        $pkg->set_file('.acl.llvmir',"$base.bc")
        or mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");
      }
      if ( $opt_only ) { return; }
    }
    if ( $run_vfabric_cfg_gen ) {
      my $debug_option = ( $debug ? '-debug' : '');
      my $vfab_lib_path = (($custom_vfab_lib_path) ? $custom_vfab_lib_path : 
      				$acl_board_hw_path."_vfabric");

      print "vfab_lib_path = $vfab_lib_path\n" if $verbose>1;

      # Check that this a valid board directory by checking for at least 1 
      # virtual fabric variant in the board directory.
      if (!-f $vfab_lib_path."/var1.txt" && !$generate_vfabric) {
        mydie("Cannot find Rapid Prototyping Library for board '$board_variant' in Rapid Prototyping flow. Run with '--create-template' flag to build new Rapid Protyping templates for this board.");
      }

      # check that this library matches the board_variant we are asked to compile to
      my $vfab_sys_file = "$vfab_lib_path/sys_description.txt";

      if (-f $vfab_sys_file) {
        open SYS_DESCR_FILE, "<$vfab_sys_file" or mydie("Invalid Rapid Prototyping Library Directory");
        my $vfab_sys_str = <SYS_DESCR_FILE>;
        chomp($vfab_sys_str);
        close SYS_DESCR_FILE;
        my @sys_split = split(' ', $vfab_sys_str);
        if ($sys_split[1] ne $board_variant) {
          mydie("Rapid Prototyping Library located in $vfab_lib_path is generated for board '$sys_split[1]' and cannot be used for board '$board_variant'.\n Please specify a different Library path.");
        }
      }
      remove_named_files("vfabv.txt");

      my $vfab_args = "-vfabric-library $vfab_lib_path";
      $vfab_args .= ($generate_vfabric ? " -generate-fabric-from-reqs " : "");
      $vfab_args .= ($reuse_vfabrics ? " -reuse-existing-fabrics " : "");

      if ($vfabric_seed) {
         $vfab_args .= " -vfabric-seed $vfabric_seed ";
      }
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'llc', 'stdout' => 'llc.log', 'stderr' => 'llc.err'},
          "$llc_exe  -VFabric -march=virtualfabric $llvm_board_option $debug_option $profile_option $vfab_args $llc_arg_after \"$base.bc\" -o \"$base.v\"" );
      filter_llvm_time_passes('llc.err');
      move_to_log("!========== [llc] vfabric ==========", 'llc.log', 'llc.err', $fulllog);
      move_to_err('llc.err');
      if ($return_status != 0) {
        if (!$generate_vfabric) {
          mydie("No suitable Rapid Prototyping templates found.\nPlease run with '--create-template' flag to build new Rapid Prototyping templates.");
        } else {
          mydie("Rapid Prototyping template generation failed.");
        }
      }

      if ( $generate_vfabric ) {
        # add the complete vfabric configuration file to the package
        $pkg->set_file('.acl.vfabric', $work_dir."/vfabric_settings.bin")
           or mydie("Can't save Rapid Prototyping configuration file into package file: $acl::Pkg::error\n");
        if ($reuse_vfabrics && open VFAB_VAR_FILE, "<vfabv.txt") {
           my $var_id = <VFAB_VAR_FILE>;
           chomp($var_id);
           close VFAB_VAR_FILE;
           acl::File::copy( $vfab_lib_path."/var".$var_id.".txt", "vfab_var1.txt" )
              or mydie("Cannot find reused template: $acl::File::error");
        }
      } else {
        # Virtual Fabric flow is done at this point (don't need to generate design)
        # But now we can go copy over the selected sof 
        open VFAB_VAR_FILE, "<vfabv.txt" or mydie("No suitable Rapid Prototyping templates found.\nPlease run with '--create-template' flag to build new Rapid Prototyping templates.");
        my $var_id = <VFAB_VAR_FILE>;
        chomp($var_id);
        close VFAB_VAR_FILE;
        print "Selected Template $var_id\n" if $verbose;

        save_vfabric_files_to_pkg($pkg, $var_id, $vfab_lib_path, $work_dir, $board_variant);

        # Save the profile XML file in the aocx
        if ( $profile ) {
          save_profiling_xml($pkg,$base);
        }

        my $board_xml = get_acl_board_hw_path($board_variant)."/board_spec.xml";
        if (-f $board_xml) {
           $pkg->set_file('.acl.board_spec.xml',"$board_xml")
                or mydie("Can't save boardspec.xml into package file: $acl::Pkg::error\n");
        }else {
           print "Cannot find board spec xml\n"
        }

        my $compilation_env = compilation_env_string($work_dir,$board_variant,$all_aoc_args);
        save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

        # Compute runtime.
        my $stage1_end_time = time();
        log_time ("virtual fabric compilation", $stage1_end_time - $stage1_start_time);

        print "$prog: Rapid Prototyping compilation completed successfully.\n" if $verbose;
        &$finalize(); 
        return;
      }
    }
  }

  my $iterationlog="iteration.tmp";
  my $iterationerr="$iterationlog.err";
  unlink $iterationlog; # Make sure we don't inherit from previous runs
  if ($griffin_flow) {
    # For the Griffin flow, we need to enable a few passes and change a few flags.
    $opt_arg_after .= " --grif --soft-elementary-math=false --fas=false --wiicm-disable=true";
  }

  while ($restart_acl) { # Might have to restart with lmem replication disabled
    unlink $iterationlog unless $save_temps;
    unlink $iterationerr; # Always remove this guy or we will get duplicates to the the screen;
    $restart_acl = 0; # Don't restart compiling unless lmem replication decides otherwise

    if ( $run_opt ) {
      print "$prog: Compiling....\n" if $verbose;
      my $debug_option = ( $debug ? '-debug' : '');
      my $profile_option = ( $profile ? '-profile' : '');

      # Opt run
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'opt', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
          "$opt_exe $opt_passes $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option $profile_option $opt_arg_after \"$optinfile\" -o \"$base.kwgid.bc\"");
      filter_llvm_time_passes('opt.err');
      append_to_log('opt.err', $iterationerr);
      move_to_log("!========== [opt] optimize ==========", 
          'opt.log', 'opt.err', $iterationlog);
      if ($return_status != 0) {
        move_to_log("", $iterationlog, $fulllog);
        move_to_err($iterationerr);
        mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

      if ( $use_ip_library && $use_ip_library_override ) {
        print "$prog: Linking with IP library ...\n" if $verbose;
        # Lower instructions to IP library function calls
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'opt (ip library prep)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe -insert-ip-library-calls $opt_arg_after \"$base.kwgid.bc\" -o \"$base.lowered.bc\"");
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [opt] ip library prep ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr);
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.kwgid.bc") unless $save_temps;

        # Link with the soft IP library 
        my $late_bc = acl::File::abs_path( acl::Env::sdk_root()."/share/lib/acl/acl_late.bc");
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'link (ip library)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$link_exe \"$base.lowered.bc\" $late_bc -o \"$base.linked.bc\"" );
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [link] ip library link ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr); 
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.lowered.bc") unless $save_temps;

        # Inline IP calls, simplify and clean up
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'opt (ip library optimize)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option -always-inline -add-inline-tag -instcombine -adjust-sizes -dce -stripnk -rename-basic-blocks $opt_arg_after \"$base.linked.bc\" -o \"$base.bc\"");
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [opt] ip library optimize ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr); 
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.linked.bc") unless $save_temps;
      } else {
        # In normal flow, lower the acl kernel workgroup id last
        $return_status = mysystem_full(
            {'time' => 1, 'time-label' => 'opt (post-process)', 'stdout' => 'opt.log', 'stderr' => 'opt.err'},
            "$opt_exe $llvm_board_option $llvm_efi_option $llvm_library_option $debug_option \"$base.kwgid.bc\" -o \"$base.bc\"");
        filter_llvm_time_passes('opt.err');
        append_to_log('opt.err', $iterationerr);
        move_to_log("!========== [opt] post-process ==========", 'opt.log', 'opt.err', $iterationlog);
        if ($return_status != 0) {
          move_to_log("", $iterationlog, $fulllog);
          move_to_err($iterationerr); 
          mydie("Optimizer FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
        }
        remove_named_files("$base.kwgid.bc") unless $save_temps;
      }
    }

    # Finish up opt-like steps.
    if ( $run_opt ) {
      if ( $disassemble || $soft_ip_c_flow ) { mysystem("llvm-dis \"$base.bc\" -o \"$base.ll\"" ) == 0 or mydie("Cannot disassemble: \"$base.bc\" \n"); }
      if ( $pkg_save_extra ) {
        $pkg->set_file('.acl.llvmir',"$base.bc")
           or mydie("Can't save optimized IR into package file: $acl::Pkg::error\n");
      }
      if ( $opt_only ) { return; }
    }

    if ( $run_verilog_gen ) {
      my $debug_option = ( $debug ? '-debug' : '');
      my $profile_option = ( $profile ? '-profile' : '');
      my $llc_option_macro = $griffin_flow ? ' -march=griffin ' : ' -march=fpga -mattr=option3wrapper -fpga-const-cache=1';

      # Run LLC
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'llc', 'stdout' => 'llc.log', 'stderr' => 'llc.err'},
          "$llc_exe $llc_option_macro $llvm_board_option $llvm_efi_option $llvm_library_option $llvm_profilerconf_option $debug_option $profile_option $llc_arg_after \"$base.bc\" -o \"$base.v\"");
      filter_llvm_time_passes('llc.err');
      append_to_log('llc.err', $iterationerr);

      move_to_log("!========== [llc] ==========", 'llc.log', 'llc.err', $iterationlog);
      if ($return_status != 0) {
        move_to_log("", $iterationlog, $fulllog);
        move_to_err($iterationerr); 
        mydie("Verilog generator FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

      # If estimate >100% of block ram, rerun opt with lmem replication disabled
      my $max_mem_percent_with_replication = 100;
      my $area_rpt_file_path = $work_dir."/area.json";
      my $xml_file_path = $work_dir."/$base.bc.xml";
      my $restart_without_lmem_replication = 0;
      if (-e $area_rpt_file_path) {
        my @area_util = get_area_percent_estimates();
        if ( $area_util[3] > $max_mem_percent_with_replication && !$disabled_lmem_replication ) {
          # Check whether memory replication was activate
          my $repl_factor_active = 0;
          if ( -e $xml_file_path ) {
            open my $xml_handle, '<', $xml_file_path or die $!;
            while ( <$xml_handle> ) {
              my $xml = $_;
              if ( $xml =~ m/.*LOCAL_MEM.*repl_fac="(\d+)".*/ ) {
                if ( $1 > 1 ) {
                  $repl_factor_active = 1;
                }
              }
            }
            close $xml_handle;
          }

          if ( $repl_factor_active ) {
            print "$prog: Restarting compile without lmem replication because of estimated overutilization!\n" if $verbose;
            $restart_without_lmem_replication = 1;
          }
        }
      } else {
        print "$prog: Cannot find area.json. Disabling lmem optimizations to be safe.\n";
        $restart_without_lmem_replication = 1;
      }
      if ( $restart_without_lmem_replication ) {
        $opt_arg_after .= $lmem_disable_replication_flag;
        $llc_arg_after .= $lmem_disable_replication_flag;
        $disabled_lmem_replication = 1;
        redo;  # Restart the compile loop
      }
    }
  } # End of while loop
  
  if (not $griffin_flow) {
    create_reporting_tool($files);
  }

  if (!$vfabric_flow) {
    move_to_log("",$iterationlog,$fulllog);
    move_to_err($iterationerr);
    remove_named_files($optinfile) unless $save_temps;
  }

  #Put after loop so we only store once
  if ( $pkg_save_extra ) { 
    $pkg->set_file('.acl.verilog',"$base.v")
      or mydie("Can't save Verilog into package file: $acl::Pkg::error\n");
  }  

  # Save the Optimization Report XML file in the aocx 
  if ( -e "opt.rpt.xml" ) {
    $pkg->add_file('.acl.opt.rpt.xml', "opt.rpt.xml")
      or mydie("Can't save opt.rpt.xml into package file: $acl::Pkg::error\n");
  }

  # Save Loops Report JSON file 
  if ( -e "loops.json" ) {
    $pkg->add_file('.acl.loops.json', "loops.json")
      or mydie("Can't save loops.json into package file: $acl::Pkg::error\n");
    remove_named_files("loops.json") unless $save_temps;
  }

  # Save Memory Architecture View JSON file 
  if ( -e "mav.json" ) {
    $pkg->add_file('.acl.mav.json', "mav.json")
      or mydie("Can't save mav.json into package file: $acl::Pkg::error\n");
    remove_named_files("mav.json") unless $save_temps;
  }

  # Save Old Memory Architecture View JSON file 
  if ( -e "mav_old.json" ) {
    $pkg->add_file('.acl.mav_old.json', "mav_old.json")
      or mydie("Can't save mav_old.json into package file: $acl::Pkg::error\n");
    remove_named_files("mav_old.json") unless $save_temps;
  }

  # Save Area Report JSON file
  # This file is removed after we get the information needed to
  # generate the Estimated Resource Usage Summary table.
  if ( -e "area.json" ) {
    $pkg->add_file('.acl.area.json', "area.json")
      or mydie("Can't save area.json into package file: $acl::Pkg::error\n");
  }
  
  # Save Area Report HTML file
  if ( -e "area.html" ) {
    $pkg->add_file('.acl.area.html', "area.html")
      or mydie("Can't save area.html into package file: $acl::Pkg::error\n");
    remove_named_files("area.html") unless $save_temps;
  }
  elsif ( $verbose > 0 ) {
    print "Missing area report information. aocl analyze-area will " .
          "not be able to generate the area report.\n";
  }
  # Save the profile XML file in the aocx
  if ( $profile ) {
    save_profiling_xml($pkg,$base);
  }

  # Move over the Optimization Report to the log file 
  if ( -e "opt.rpt" ) {
    append_to_log( "opt.rpt", $fulllog );
    unlink "opt.rpt" unless $save_temps;
  }

  unlink "report.out";
  if (( $estimate_throughput ) && ( !$accel_gen_flow ) && ( !$soft_ip_c_flow )) {
      print "Estimating throughput since \$estimate_throughput=$estimate_throughput\n";
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'opt (throughput)', 'stdout' => 'report.out', 'stderr' => 'report.err'},
        "$opt_exe -print-throughput -throughput-print $llvm_board_option $opt_arg_after \"$base.bc\" -o $base.unused" );
    filter_llvm_time_passes("report.err");
    move_to_err_and_log("Throughput analysis","report.err",$fulllog);
  }
  unlink "$base.unused";

  # Guard probably depricated, if we get here we should have verilog, was only used by vfabric
  if ( $run_verilog_gen && !$vfabric_flow) {

    # Round these numbers properly instead of just truncating them.
    my @all_util = get_area_percent_estimates();
    remove_named_files("area.json") unless $save_temps;

    open LOG, ">>report.out";
    printf(LOG "\n".
          "+--------------------------------------------------------------------+\n".
          "; Estimated Resource Usage Summary                                   ;\n".
          "+----------------------------------------+---------------------------+\n".
          "; Resource                               + Usage                     ;\n".
          "+----------------------------------------+---------------------------+\n".
          "; Logic utilization                      ; %4d\%                     ;\n".
          "; ALUTs                                  ; %4d\%                     ;\n".
          "; Dedicated logic registers              ; %4d\%                     ;\n".
          "; Memory blocks                          ; %4d\%                     ;\n".
          "; DSP blocks                             ; %4d\%                     ;\n".
          "+----------------------------------------+---------------------------;\n",
          $all_util[0], $all_util[1], $all_util[2], $all_util[3], $all_util[4]);
    close LOG;

    append_to_log ("report.out", $fulllog);
  }
  if ($report) {
    open LOG, "<report.out";
    print STDOUT <LOG>;
    close LOG;
  }
  unlink "report.out" unless $save_temps;

  if ($save_last_bc) {
    $pkg->set_file('.acl.profile_base',"$base.bc")
      or mydie("Can't save profiling base listing into package file: $acl::Pkg::error\n");
  }
  remove_named_files("$base.bc") unless $save_temps or $save_last_bc;

  my $xml_file = "$base.bc.xml";
  my $sysinteg_debug .= ($debug ? "-v" : "" );

  if ($vfabric_flow) {
    $xml_file = "virtual_fabric.bc.xml";
    $sysinteg_arg_after .= ' --vfabric ';
  }

  my $version = ::acl::Env::aocl_boardspec( ".", "version");
  my $generic_kernel = ::acl::Env::aocl_boardspec( ".", "generic_kernel");
  my $qsys_file = ::acl::Env::aocl_boardspec( ".", "qsys_file");

  if ( $generic_kernel or ($version eq "0.9" and -e "base.qsf")) 
  {
    if ($qsys_file eq "none") {
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
          "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" none kernel_system.tcl" );
    } else {
      $return_status = mysystem_full(
          {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
          "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" system.tcl kernel_system.tcl" );
    }
  } else {
    if ($qsys_file eq "none") {
      mydie("A board with 'generic_kernel' set to \"0\" and 'qsys_file' set to \"none\" is an invalid combination in board_spec.xml! Please revise your BSP for errors!\n");  
    }
    $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'system integrator', 'stdout' => 'si.log', 'stderr' => 'si.err'},
        "$sysinteg_exe $sysinteg_debug $sysinteg_arg_after $board_spec_xml \"$xml_file\" system.tcl" );
  }
  move_to_log("!========== [SystemIntegrator] ==========", 'si.log', $fulllog);
  move_to_err_and_log("",'si.err', $fulllog);
  $return_status == 0 or mydie("System integrator FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

  #Issue an error if autodiscovery string is larger than 4k (only for version < 15.1).
  my $bsp_version = acl::Env::aocl_boardspec( "$board_spec_xml", "version");
  if( (-s "sys_description.txt" > 4096) && ($bsp_version < 15.1) ) {
    mydie("System integrator FAILED.\nThe autodiscovery string cannot be more than 4096 bytes\n");
  }
  $pkg->set_file('.acl.autodiscovery',"sys_description.txt")
    or mydie("Can't save system description into package file: $acl::Pkg::error\n");

  if(-f "autodiscovery.xml") {
    $pkg->set_file('.acl.autodiscovery.xml',"autodiscovery.xml")
      or mydie("Can't save system description xml into package file: $acl::Pkg::error\n");    
  } else {
     print "Cannot find autodiscovery xml\n";
  }  

  if(-f "board_spec.xml") {
    $pkg->set_file('.acl.board_spec.xml',"board_spec.xml")
      or mydie("Can't save boardspec.xml into package file: $acl::Pkg::error\n");
  } else {
     print "Cannot find board spec xml\n";
  } 

  if(-f "kernel_arg_info.xml") {
    $pkg->set_file('.acl.kernel_arg_info.xml',"kernel_arg_info.xml");
    unlink 'kernel_arg_info.xml' unless $save_temps;
  } else {
     print "Cannot find kernel arg info xml.\n" if $verbose;
  }

  my $compilation_env = compilation_env_string($work_dir,$board_variant,$all_aoc_args);
  save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

  print "$prog: First stage compilation completed successfully.\n" if $verbose;
  # Compute aoc runtime WITHOUT Quartus time or integration, since we don't control that
  my $stage1_end_time = time();
  log_time ("first compilation stage", $stage1_end_time - $stage1_start_time);

  if ( $verilog_gen_only || $accel_gen_flow ) { return; }

  &$finalize();
#aoc: Adding SEARCH_PATH assignment to /data/thoffner/trees/opencl/p4/regtest/opencl/aoc/aoc_flow/test/gurka/top.qsf

  my $file_name = "$base.aoco";
  if ( $output_file_arg ) {
      $file_name = $output_file_arg;
  }
  print "$prog: To compile this project, run \"$prog $file_name\"\n" if $verbose && $compile_step;
}

sub compile_design {
  my ($base,$work_dir,$obj,$x_file,$board_variant,$all_aoc_args) = @_;
  $fulllog = "$base.log"; #definition moved to global space
  my $pkgo_file = $obj; # Should have been created by first phase.
  my $pkg_file_final = $output_file || acl::File::abs_path("$base.aocx");
  $pkg_file = $pkg_file_final.".tmp";

  # OK, no turning back remove the result file, so no one thinks we succedded
  unlink $pkg_file_final;
  #Create the new direcory verbatim, then rewrite it to not contain spaces
  $work_dir = $work_dir;

  # To support relative BSP paths, access this before changing dir
  my $postqsys_script = acl::Env::board_post_qsys_script();

  chdir $work_dir or mydie("Can't change dir into $base: $!");

  # First, look in the pkg file to see if there were virtual fabric binaries
  # If there are, that means the previous compile was a vfabric run, and 
  # there is no hardware to build
  acl::File::copy( $pkgo_file, $pkg_file )
   or mydie("Can't copy binary package file $pkgo_file to $pkg_file: $acl::File::error");
  my $pkg = get acl::Pkg($pkg_file)
     or mydie("Can't find package file: $acl::Pkg::error\n");

  #Remember the reason we are here, can't query pkg_file after rename
  my $emulator = $pkg->exists_section('.acl.emulator_object.linux') ||
      $pkg->exists_section('.acl.emulator_object.windows');

  # Store a random hash, and the inputs to quartus hash, in pkg. Should be added before quartus adds new HDL files to the working dir.
  add_hash_sections($work_dir,$board_variant,$pkg_file,$all_aoc_args);

  if ( ! $no_automigrate && ! $emulator) {
    acl::Board_migrate::migrate_platform_preqsys();
  }

  # Set version again, for informational purposes.
  # Do it again, because the second half flow is more authoritative
  # about the executable contents of the package file.
  save_pkg_section($pkg,'.acl.version',acl::Env::sdk_version());

  if (($pkg->exists_section('.acl.vfabric') && 
      $pkg->exists_section('.acl.fpga.bin')) ||
      $pkg->exists_section('.acl.emulator_object.linux') ||
     $pkg->exists_section('.acl.emulator_object.windows'))
  {
     unlink( $pkg_file_final ) if -f $pkg_file_final;
     rename( $pkg_file, $pkg_file_final )
       or mydie("Can't rename $pkg_file to $pkg_file_final: $!");

     if (!$emulator) {
         print "Rapid Prototyping flow is successful.\n" if $verbose;
     } else {
	 print "Emulator flow is successful.\n" if $verbose;
	 print "To execute emulated kernel, invoke host with \n\tenv CL_CONTEXT_EMULATOR_DEVICE_ALTERA=1 <host_program>\n For multi device emulations replace the 1 with the number of devices you wish to emulate\n" if $verbose;

     }
     return;
  }

  # If we have the vfabric section, but not the bin section, then
  # we are doing a vfabric compile
  if ($pkg->exists_section('.acl.vfabric') && 
      !$pkg->exists_section('.acl.fpga.bin')) {
    $generate_vfabric = 1;
  }

  if ( ! $skip_qsys) { 

    #Ignore SOPC Builder's return value
    my $sopc_builder_cmd = "qsys-script";
    my $ip_gen_cmd = "ip-generate";

    # Make sure both qsys-script and ip-generate are on the command line
    my $qsys_location = acl::File::which_full ("qsys-script"); chomp $qsys_location;
    if ( not defined $qsys_location ) {
       mydie ("Error: qsys-script executable not found!\n".
              "Add quartus bin directory to the front of the PATH to solve this problem.\n");
    }
    my $ip_gen_location = acl::File::which_full ("ip-generate"); chomp $ip_gen_location;
    if ( not defined $ip_gen_location ) {
       mydie ("Error: iop-generate executable not found!\n".
              "Add quartus bin directory to the front of the PATH to solve this problem.\n");
    }
        
    # Run Java Runtime Engine with max heap size 512MB, and serial garbage collection.
    my $jre_tweaks = "-Xmx512M -XX:+UseSerialGC";

    open LOG, "<sopc.tmp";
    while (<LOG>) { print if / Error:/; }
    close LOG;

    my $version = ::acl::Env::aocl_boardspec( ".", "version");
    my $generic_kernel = ::acl::Env::aocl_boardspec( ".", "generic_kernel");
    my $qsys_file = ::acl::Env::aocl_boardspec( ".", "qsys_file");
    my $project = ::acl::Env::aocl_boardspec( ".", "project");

    if ( $generic_kernel or ($version eq "0.9" and -e "base.qsf")) 
    {
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
        "$sopc_builder_cmd --quartus-project=$project --script=kernel_system.tcl $jre_tweaks" );
      move_to_log("!=========Qsys kernel_system script===========", "sopc.tmp", $fulllog);
      $return_status == 0 or  mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
 
      if (!($qsys_file eq "none"))
      {
        $return_status =mysystem_full(
          {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
          "$sopc_builder_cmd --quartus-project=$project --script=system.tcl $jre_tweaks --system-file=$qsys_file" );
        move_to_log("!=========Qsys system script===========", "sopc.tmp", $fulllog);
        $return_status == 0 or  mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
      }

    } else {
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'sopc builder', 'stdout' => 'sopc.tmp', 'stderr' => '&STDOUT'},
        "$sopc_builder_cmd --quartus-project=$project --script=system.tcl $jre_tweaks --system-file=$qsys_file" );
      move_to_log("!=========Qsys script===========", "sopc.tmp", $fulllog);
      $return_status == 0 or  mydie("Qsys-script FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");
    }

    if ($simulation_mode) {
      print "Qsys ip-generate (simulation mode) started!\n" ;      
      $return_status = mysystem_full( 
        {'time' => 1, 'time-label' => 'ip generate (simulation), ', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
      "$ip_gen_cmd --component-file=$qsys_file --file-set=SIM_VERILOG --component-param=CALIBRATION_MODE=Skip  --output-directory=system/simulation --report-file=sip:system/simulation/system.sip --jvm-max-heap-size=3G" );                           
      print "Qsys ip-generate done!\n" ;            
    } else {      
      my $generate_cmd = ::acl::Env::aocl_boardspec( ".", "generate_cmd");

      $return_status = mysystem_full( 
        {'time' => 1, 'time-label' => 'ip generate', 'stdout' => 'ipgen.tmp', 'stderr' => '&STDOUT'},
        "$generate_cmd" );  
    }

    open LOG, "<ipgen.tmp";
    while (<LOG>) { print if / Error:/; }
    close LOG;
    move_to_log("!=========ip-generate===========","ipgen.tmp",$fulllog);
    $return_status == 0 or mydie("ip-generate FAILED.\nRefer to ".acl::File::mybasename($work_dir)."/$fulllog for details.\n");

    # Some boards may post-process qsys output
    if (defined $postqsys_script and $postqsys_script ne "") {
      mysystem( "$postqsys_script" ) == 0 or mydie("Couldn't run postqsys-script for the board!\n");
    }

    print_bsp_msgs($fulllog);

  }

  # Override the fitter seed, if specified.
  if ( $fit_seed ) {
    my @designs = acl::File::simple_glob( "*.qsf" );
    $#designs > -1 or mydie ("Internal Compiler Error.  Seed argument was passed but could not find any qsf files\n");
    foreach (@designs) {
      my $qsf = $_;
      $return_status = mysystem( "echo \"\nset_global_assignment -name SEED $fit_seed\n\" >> $qsf" );
    }
  }

  # Add DSP location constraints, if specified.
  if ( $dsploc ) {
    extract_atoms_from_postfit_netlist($base,$dsploc,"DSP");
  } 

  # Add RAM location constraints, if specified.
  if ( $ramloc ) {
    extract_atoms_from_postfit_netlist($base,$ramloc,"RAM"); 
  } 

  if ( $ip_gen_only ) { return; }

  # "Old --hw" starting point
  my $project = ::acl::Env::aocl_boardspec( ".", "project");
  my @designs = acl::File::simple_glob( "$project.qpf" );
  $#designs >= 0 or mydie ("Internal Compiler Error.  BSP specified project name $project, but $project.qpf does not exist.\n");
  $#designs == 0 or mydie ("Internal Compiler Error.\n");
  my $design = shift @designs;

  my $synthesize_cmd = ::acl::Env::aocl_boardspec( ".", "synthesize_cmd");

  my $retry = 0;
  my $MAX_RETRIES = 3;
  if ($high_effort) {
    print "High-effort hardware generation selected, compile time may increase signficantly.\n";
  }

  do {

    if (defined $ENV{ACL_QSH_COMPILE_CMD})
    {
      # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default
      # quartus compile command (internal use only).  
      my $top = acl::File::mybasename($design); 
      $top =~ s/\.qpf//;
      my $custom_cmd = $ENV{ACL_QSH_COMPILE_CMD};
      $custom_cmd =~ s/PROJECT/$top/;
      $custom_cmd =~ s/REVISION/$top/;
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'Quartus compilation', 'stdout' => 'quartus_sh_compile.log'},
        $custom_cmd);
    } else {
      $return_status = mysystem_full(
        {'time' => 1, 'time-label' => 'Quartus compilation', 'stdout' => 'quartus_sh_compile.log', 'stderr' => 'quartuserr.tmp'},
        $synthesize_cmd);
    }

    print_bsp_msgs('quartus_sh_compile.log');

    if ( $return_status != 0 ) {
      if ($high_effort && hard_routing_error('quartus_sh_compile.log') && $retry < $MAX_RETRIES) {
        print " kernel fitting error encountered - retrying aocx compile.\n";
        $retry = $retry + 1;

        # Override the fitter seed, if specified.
        my @designs = acl::File::simple_glob( "*.qsf" );
        $#designs > -1 or print_quartus_errors('quartus_sh_compile.log', 0);
        my $seed = $retry * 10;
        foreach (@designs) {
          my $qsf = $_;
          if ($retry > 1) {
            # Remove the old seed setting
            open( my $read_fh, "<", $qsf ) or mydie("Unexpected Compiler Error, not able to generate hardware in high effort mode.");
            my @file_lines = <$read_fh>; 
            close( $read_fh ); 

            open( my $write_fh, ">", $qsf ) or mydie("Unexpected Compiler Error, not able to generate hardware in high effort mode.");
            foreach my $line ( @file_lines ) { 
              print {$write_fh} $line unless ( $line =~ /set_global_assignment -name SEED/ ); 
            } 
            print {$write_fh} "set_global_assignment -name SEED $seed\n";
            close( $write_fh ); 
          } else {
            $return_status = mysystem( "echo \"\nset_global_assignment -name SEED $seed\n\" >> $qsf" );
          }
        }
      } else {
        $retry = 0;
        print_quartus_errors('quartus_sh_compile.log', $high_effort == 0);
      }
    } else {
      $retry = 0;
    }
  } while ($retry && $retry < $MAX_RETRIES);


  # check sta log for timing not met warnings
  print "$prog: Hardware generation completed successfully.\n" if $verbose;

  my $fpga_bin = 'fpga.bin';
  if ( -f $fpga_bin ) {
    $pkg->set_file('.acl.fpga.bin',$fpga_bin)
       or mydie("Can't save FPGA configuration file $fpga_bin into package file: $acl::Pkg::error\n");

    if ($generate_vfabric) { # need to save this to the board path
        my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
        my $vfab_lib_path = (($custom_vfab_lib_path) ? $custom_vfab_lib_path : 
      				$acl_board_hw_path."_vfabric");
        my $num_templates_file = "$vfab_lib_path/num_templates.txt";
        my $dir_writeable = 1;
        my $var_id = 0;

        # create the directory if necessary
        if (!-f $num_templates_file) { 
           $dir_writeable = acl::File::make_path($vfab_lib_path);
           if ($dir_writeable) {
              $dir_writeable = open (VFAB_NUM_TMP_FILE, '>', $num_templates_file);
              if ($dir_writeable) {
                 print VFAB_NUM_TMP_FILE "$var_id\n";
                 close VFAB_NUM_TMP_FILE;
              }
           }
        } else { #templates file already exist: read variant number
          open VFAB_NUM_TMP_FILE, "<$num_templates_file" or mydie("Invalid template directory");
          $var_id = <VFAB_NUM_TMP_FILE>;
          chomp($var_id);
          close VFAB_NUM_TMP_FILE;
        }
        $var_id++;

        if (!$reuse_vfabrics && open (VFAB_NUM_TMP_FILE, '>', $num_templates_file)) {
          acl::File::copy( "vfab_var1.txt", $vfab_lib_path."/var".$var_id.".txt" )
            or mydie("Can't copy created template vfab_var1.txt to $vfab_lib_path/var$var_id.txt: $acl::File::error");
          acl::File::copy( $fpga_bin, $vfab_lib_path."/var".$var_id.".fpga.bin" )
            or mydie("Can't copy created template fpga.bin to $vfab_lib_path/var$var_id.fpga.bin: $acl::File::error");
          acl::File::copy( "acl_quartus_report.txt", $vfab_lib_path."/var".$var_id.".acl_quartus_report.txt" )
            or mydie("Can't copy created template acl_quartus_report.txt to $vfab_lib_path/var$var_id.acl_quartus_report.txt: $acl::File::error");
          if (! -f "$vfab_lib_path./sys_description.txt") {
             acl::File::copy( "sys_description.txt", $vfab_lib_path."/sys_description.txt" )
               or mydie("Can't copy sys_description.txt to $vfab_lib_path/sys_description.txt: $acl::File::error");
          }

          print "Successfully created Rapid Prototyping Template $var_id\n";

          save_vfabric_files_to_pkg($pkg, $var_id, $vfab_lib_path, ".", $board_variant);

	  # update the number of templates there are in the directory
          print VFAB_NUM_TMP_FILE $var_id;
          close VFAB_NUM_TMP_FILE;
        } else {
          print "Cannot save generated Rapid Prototyping Template to directory $vfab_lib_path. May not have write permissions.\n\n";
          print "To reuse this Template in a future kernel compile, please manually save the following files:\n";
          print " - vfab_var1.txt as $vfab_lib_path"."/var".$var_id.".txt\n";
          print " - fpga.bin as $vfab_lib_path"."/var".$var_id.".fpga.bin\n";
          print " - acl_quartus_report.txt as $vfab_lib_path"."/var".$var_id.".acl_quartus_report.txt\n";
          print " - sys_description.txt as $vfab_lib_path"."/sys_description.txt if missing\n";
          print "\nPlease increment ".$vfab_lib_path."/num_templates.txt to include this Template\n";
        }
    }

  } else { #If fpga.bin not found, package up sof and core.rbf

    # Save the SOF in the package file.
    my @sofs = (acl::File::simple_glob( "*.sof" ));
    if ( $#sofs < 0 ) {
      print "$prog: Warning: Cannot find a FPGA programming (.sof) file\n";
    } else {
      if ( $#sofs > 0 ) {
        print "$prog: Warning: Found ".(1+$#sofs)." FPGA programming files. Using the first: $sofs[0]\n";
      }
      $pkg->set_file('.acl.sof',$sofs[0])
        or mydie("Can't save FPGA programming file into package file: $acl::Pkg::error\n");
    }
    # Save the RBF in the package file, if it exists.
    # Sort by name instead of leaving it random.
    # Besides, sorting will pick foo.core.rbf over foo.periph.rbf
    foreach my $rbf_type ( qw( core periph ) ) {
      my @rbfs = sort { $a cmp $b } (acl::File::simple_glob( "*.$rbf_type.rbf" ));
      if ( $#rbfs < 0 ) {
        #     print "$prog: Warning: Cannot find a FPGA core programming (.rbf) file\n";
      } else {
        if ( $#rbfs > 0 ) {
          print "$prog: Warning: Found ".(1+$#rbfs)." FPGA $rbf_type.rbf programming files. Using the first: $rbfs[0]\n";
        }
        $pkg->set_file(".acl.$rbf_type.rbf",$rbfs[0])
          or mydie("Can't save FPGA $rbf_type.rbf programming file into package file: $acl::Pkg::error\n");
      }
    }
  }

  my $pll_config = 'pll_config.bin';
  if ( -f $pll_config ) {
    $pkg->set_file('.acl.pll_config',$pll_config)
       or mydie("Can't save FPGA clocking configuration file $pll_config into package file: $acl::Pkg::error\n");
  }

  my $acl_quartus_report = 'acl_quartus_report.txt';
  if ( -f $acl_quartus_report ) {
    $pkg->set_file('.acl.quartus_report',$acl_quartus_report)
       or mydie("Can't save Quartus report file $acl_quartus_report into package file: $acl::Pkg::error\n");
  }

  unlink( $pkg_file_final ) if -f $pkg_file_final;
  rename( $pkg_file, $pkg_file_final )
    or mydie("Can't rename $pkg_file to $pkg_file_final: $!");

  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");
  remove_intermediate_files($work_dir,$pkg_file_final) if $tidy;
}

# Some aoc args translate to args to many underlying exes.
sub process_meta_args {
  my ($cur_arg, $argv) = @_;
  my $processed = 0;
  if ($cur_arg eq '--1x-clock-for-local-mem') {
    # TEMPORARY: don't actually enforce this flag
    #$opt_arg_after .= ' -force-1x-clock-local-mem';
    #$llc_arg_after .= ' -force-1x-clock-local-mem';
    #$sysinteg_arg_after .= ' --cic-1x-local-mem';
    $processed = 1;
  }
  elsif ( ($cur_arg eq '--sw_dimm_partition') or ($cur_arg eq '--sw-dimm-partition')) {
    # TODO need to do this some other way
    # this flow is incompatible with the dynamic board selection (--board)
    # because it overrides the board setting
    $sysinteg_arg_after .= ' --cic-global_no_interleave ';
    $processed = 1;
  }

  return $processed;
}

# Deal with multiple specified source files
sub process_input_file_arguments {

  if ($#given_input_files == -1) {
    # No input files are given
    return "";
  }

  # Only multiple .cl files are allowed. Can't mix
  # .aoco and .cl, for example.  
  my %suffix_cnt;
  foreach my $gif (@given_input_files) {
    my $suffix = $gif;
    $suffix =~ s/.*\.//;
    $suffix =~ tr/A-Z/a-z/;
    $suffix_cnt{$suffix}++;
  }

  # Error checks, even for one file
    
  if ($suffix_cnt{'c'} > 0 and !($soft_ip_c_flow || $c_acceleration)) {
    # Pretend we never saw it i.e. issue the same message as we would for 
    # other not recognized extensions. Not the clearest message, 
    # but at least consistent
    mydie("No recognized input file format on the command line");
  }
  
  # If have multiple files, they should all be .cl files.
  if ($#given_input_files > 0 and ($suffix_cnt{'cl'} < $#given_input_files-1)) {
    # Have some .cl files but not ALL .cl files. Not allowed.
    mydie("If multiple input files are specified, all must be .cl files.\n");
  }
  
  # Make sure aoco file is not an HDL component package
  if ($suffix_cnt{'aoco'} > 0) {
    # At this point, know that have a single input file.
    system(acl::Env::sdk_pkg_editor_exe(), $given_input_files[0], 'exists', '.comp_header');
    if ($? == 0) {
      mydie("Specified aoco file is a HDL component package. It cannot be used by itself to do hardware compiles!\n");
    }
  }

  # For emulation flow, if library(ies) are specified, 
  # extract all C model files and add them to the input file list.
  if ($emulator_flow and $#resolved_lib_files > -1) {
    
    # C model files from libraries will be extracted to this folder
    my $c_model_folder = ".emu_models";
    
    # If it already exists, clean it out.
    if (-d $c_model_folder) {
      chdir $c_model_folder or die $!;
        opendir (DIR, ".") or die $!;
        while (my $file = readdir(DIR)) {
          if ($file ne "." and $file ne "..") {
            unlink $file;
          }
        }
        closedir(DIR);
      chdir ".." or die $!;
    } else {
      mkdir $c_model_folder or die $!;
    }
    
    my @c_model_files;
    foreach my $libfile (@resolved_lib_files) {
      my $new_files = `$aocl_libedit_exe extract_c_models \"$libfile\" $c_model_folder`;
      push @c_model_files, split /\n/, $new_files;
    }
    
    # Add library files to the front of file list.
    if ($verbose) {
      print "All OpenCL C models were extracted from specified libraries and added to compilation\n";
    }
    @given_input_files = (@c_model_files, @given_input_files);
  }
  
  
  my $gathering_fname = "__all_sources.cl";
  if ($#given_input_files == 0) {
    # Only one input file, don't bother grouping
    $gathering_fname = $given_input_files[-1]; 
  } else {
    if ($verbose) {
      print "All input files will be grouped into one by $gathering_fname\n";
    }
    open (my $out, ">", $gathering_fname) or die "Couldn't create a file \"$gathering_fname\"!\n";
    foreach my $gif (@given_input_files) {
      -e $gif or mydie("Specified input file $gif does not exist.\n");
      print $out "#include \"$gif\"\n";
    }
    close $out;
  }
  
  # Make 'base' name for all naming purposes (subdir, aoco/aocx files) to 
  # be based on the last source file. Otherwise, it will be __all_sources, 
  # which is unexpected.
  my $last_src_file = $given_input_files[-1];
  
  return ($gathering_fname, acl::File::mybasename($last_src_file));
}


# List installed boards.
sub list_boards {
  print "Board list:\n";

  my %boards = acl::Env::board_hw_list();
  if( keys( %boards ) == -1 ) {
    print "  none found\n";
  }
  else {
    for my $b ( sort keys %boards ) {
      my $boarddir = $boards{$b};
      print "  $b\n";
      if ( ::acl::Env::aocl_boardspec( $boarddir, "numglobalmems") > 1 ) {
        my $gmemnames = ::acl::Env::aocl_boardspec( $boarddir, "globalmemnames");
        print "     Memories: $gmemnames\n";
      }
      my $channames = ::acl::Env::aocl_boardspec( $boarddir, "channelnames");
      if ( length $channames > 0 ) {
        print "     Channels: $channames\n";
      }
      print "\n";
    }
  }
}


sub usage() {
  my $default_board_text;
  my $board_env = &acl::Board_env::get_board_path() . "/board_env.xml";

  if (-e $board_env) {
    my $default_board;
    ($default_board) = &acl::Env::board_hardware_default();
    $default_board_text = "Default is $default_board.";
  } else {
    $default_board_text = "Cannot find default board location or default board name.";
  }
  print <<USAGE;

aoc -- Intel(R) FPGA SDK for OpenCL(TM) Kernel Compiler

Usage: aoc <options> <file>.[cl|aoco]

Example:
       # First generate an <file>.aoco file
       aoc -c mykernels.cl
       # Now compile the project into a hardware programming file <file>.aocx.
       aoc mykernels.aoco
       # Or generate all at once
       aoc mykernels.cl

Outputs:
       <file>.aocx and/or <file>.aoco

Help Options:
--version
          Print out version infomation and exit

-v        
          Verbose mode. Report progress of compilation

--report  
          Print area estimates to screen after intial 
          compilation. The report is always written to the log file.

-h
--help    
          Show this message

Overall Options:
-c        
          Stop after generating a <file>.aoco

-o <output> 
          Use <output> as the name for the output.
          If running with the '-c' option the output file extension should be '.aoco'.
          Otherwise the file extension should be '.aocx'.
          If neither extension is specified, the appropriate extension will be added automatically.

-march=emulator
          Create kernels that can be executed on x86

-g        
          Add debug data to kernels. Also, makes it possible to symbolically
          debug kernels created for the emulator on an x86 machine (Linux only).
          This behavior is enabled by default. This flag may be used to override the -g0 flag.

-g0        
          Don't add debug data to kernels.

--profile
          Enable profile support when generating aocx file. Note that
          this does have a small performance penalty since profile
          counters will be instantiated and take some some FPGA
          resources.
	  
-shared
          Compile OpenCL source file into an object file that can be included into
          a library. Implies -c. 

-I <directory> 
          Add directory to header search path.
          
-L <directory>
          Add directory to OpenCL library search path.
          
-l <library.aoclib>
          Specify OpenCL library file.

-D <name> 
          Define macro, as name=value or just name.

-W        
          Suppress warning.

-Werror   
          Make all warnings into errors.

--library-debug Generate debug output related to libraries.

Modifiers:
--board <board name>
          Compile for the specified board. $default_board_text

--list-boards
          Print a list of available boards and exit.

Optimization Control:

--no-interleaving <global memory name>
          Configure a global memory as separate address spaces for each
          DIMM/bank.  User should then use the Altera specific cl_mem_flags
          (E.g.  CL_MEM_BANK_2_ALTERA) to allocate each buffer in one DIMM or
          the other. The argument 'default' can be used to configure the default
          global memory. Consult your board's documentation for the memory types
          available. See the Best Practices Guide for more details.

--const-cache-bytes <N>
          Configure the constant cache size (rounded up to closest 2^n).
	  If none of the kernels use the __constant address space, this 
	  argument has no effect. 

--fp-relaxed
          Allow the compiler to relax the order of arithmetic operations,
          possibly affecting the precision

--fpc 
          Removes intermediary roundings and conversions when possible, 
          and changes the rounding mode to round towards zero for 
          multiplies and adds

--high-effort
          Increases aocx compile effort to improve ability to fit
	  kernel on the device.

-cl-single-precision-constant
-cl-denorms-are-zero
-cl-opt-disable
-cl-strict-aliasing
-cl-mad-enable
-cl-no-signed-zeros
-cl-unsafe-math-optimizations
-cl-finite-math-only
-cl-fast-relaxed-math
           OpenCL required options. See OpenCL specification for details


USAGE
#--initial-dir <dir>
#          Run the parser from the given directory.  
#          The default is to run the parser in the current directory.

#          Use this option to properly resolve relative include 
#          directories when running the compiler in a directory other
#          than where the source file may be found.
#--save-extra
#          Save kernel program source, optimized intermediate representation,
#          and Verilog into the program package file.
#          By default, these items are not saved.
#
#--no-env-check
#          Skip environment checks at startup.
#          Use this option to save a few seconds of runtime if you 
#          already know the environment is set up to run the Intel(R) FPGA SDK
#          for OpenCL(TM) compiler.
#--dot
#          Dump out DOT graph of the kernel pipeline.

}


sub powerusage() {
  print <<POWERUSAGE;

aoc -- Intel(R) FPGA SDK for OpenCL(TM) Kernel Compiler

Usage: aoc <options> <file>.[cl|aoco]

Help Options:

--powerhelp    
          Show this message

Modifiers:
--seed <value>
          Run the Quartus compile with a seed value of <value>. Default is '1'. 

--dsploc <compile directory>
          Extract DSP locations from given <compile directory> post-fit netlist and use them in current Quartus compile

--ramloc <compile directory>
          Extract RAM locations from given <compile directory> post-fit netlist and use them in current Quartus compile

POWERUSAGE

}


sub version($) {
  my $outfile = $_[0];
  print $outfile "Intel(R) FPGA SDK for OpenCL(TM), 64-Bit Offline Compiler\n";
  print $outfile "Version 16.1.0 Build 192\n";
  print $outfile "Copyright (C) 2016 Intel Corporation\n";
}


sub compilation_env_string($$$){
  my ($work_dir,$board_variant,$input_args) = @_;
  #Case:354532, not handling relative address for AOCL_BOARD_PACKAGE_ROOT correctly.
  my $starting_dir = acl::File::abs_path('.');  #keeping to change back to this dir after being done.
  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");

  # Gathering all options and tool versions.
  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  my $board_spec_xml = find_board_spec($acl_board_hw_path);
  my $platform_type = acl::Env::aocl_boardspec( "$board_spec_xml", "automigrate_type");
  my $build_number = "192";
  my $acl_Version = "16.1.0";
  my $clang_version = `$clang_exe --version`;
  $clang_version =~ s/\s+/ /g; #replacing all white spaces with space
  my $llc_version = `$llc_exe --version`;
  $llc_version =~ s/\s+/ /g; #replacing all white spaces with space
  my $sys_integrator_version = `$sysinteg_exe --version`;
  $sys_integrator_version =~ s/\s+/ /g; #replacing all white spaces with space
  my $lib_path = "$ENV{'LD_LIBRARY_PATH'}";
  my $board_pkg_root = "$ENV{'AOCL_BOARD_PACKAGE_ROOT'}";
  if (!$QUARTUS_VERSION) {
    $QUARTUS_VERSION = `quartus_sh --version`;
  }
  my $quartus_version = $QUARTUS_VERSION;
  $quartus_version =~ s/\s+/ /g; #replacing all white spaces with space

  # Quartus compile command
  my $synthesize_cmd = ::acl::Env::aocl_boardspec( $acl_board_hw_path, "synthesize_cmd");
  my $acl_qsh_compile_cmd="$ENV{'ACL_QSH_COMPILE_CMD'}"; # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default quartus compile command (internal use only).

  # Concatenating everything
  my $res = "";
  $res .= "INPUT_ARGS=".$input_args."\n";
  $res .= "BUILD_NUMBER=".$build_number."\n";
  $res .= "ACL_VERSION=".$acl_Version."\n";
  $res .= "OPERATING_SYSTEM=$^O\n";
  $res .= "BOARD_SPEC_XML=".$board_spec_xml."\n";
  $res .= "PLATFORM_TYPE=".$platform_type."\n";
  $res .= "CLANG_VERSION=".$clang_version."\n";
  $res .= "LLC_VERSION=".$llc_version."\n";
  $res .= "SYS_INTEGRATOR_VERSION=".$sys_integrator_version."\n";
  $res .= "LIB_PATH=".$lib_path."\n";
  $res .= "AOCL_BOARD_PKG_ROOT=".$board_pkg_root."\n";
  $res .= "QUARTUS_VERSION=".$quartus_version."\n";
  $res .= "QUARTUS_OPTIONS=".$synthesize_cmd."\n";
  $res .= "ACL_QSH_COMPILE_CMD=".$acl_qsh_compile_cmd."\n";

  chdir $starting_dir or mydie("Can't change back into directory $starting_dir: $!"); # Changing back to the dir I started with
  return $res;
}

# Addes a unique hash for the compilatin, and a section that contains 3 hashes for the state before quartus compile.
sub add_hash_sections($$$$) {
  my ($work_dir,$board_variant,$pkg_file,$input_args) = @_;
  my $pkg = get acl::Pkg($pkg_file) or mydie("Can't find package file: $acl::Pkg::error\n");

  #Case:354532, not handling relative address for AOCL_BOARD_PACKAGE_ROOT correctly.
  my $starting_dir = acl::File::abs_path('.');  #keeping to change back to this dir after being done.
  chdir $orig_dir or mydie("Can't change back into directory $orig_dir: $!");

  my $compilation_env = compilation_env_string($work_dir,$board_variant,$input_args);

  save_pkg_section($pkg,'.acl.compilation_env',$compilation_env);

  # Random unique hash for this compile:
  my $hash_exe = acl::Env::sdk_hash_exe();
  my $temp_hashed_file="$work_dir/hash.tmp"; # Temporary file that is used to pass in strings to aocl-hash
  my $ftemp;
  my $random_hash_key;
  open($ftemp, '>', $temp_hashed_file) or die "Could not open file $!";
  my $rand_key = rand;
  print $ftemp "$rand_key\n$compilation_env";
  close $ftemp;


  $random_hash_key = `$hash_exe \"$temp_hashed_file\"`;
  unlink $temp_hashed_file;
  save_pkg_section($pkg,'.acl.rand_hash',$random_hash_key);

  # The hash of inputs and options to quartus + quartus versions:
  my $before_quartus;

  my $acl_board_hw_path= get_acl_board_hw_path($board_variant);
  if (!$QUARTUS_VERSION) {
    $QUARTUS_VERSION = `quartus_sh --version`;
  }
  my $quartus_version = $QUARTUS_VERSION;
  $quartus_version =~ s/\s+/ /g; #replacing all white spaces with space

  # Quartus compile command
  my $synthesize_cmd = ::acl::Env::aocl_boardspec( $acl_board_hw_path, "synthesize_cmd");
  my $acl_qsh_compile_cmd="$ENV{'ACL_QSH_COMPILE_CMD'}"; # Environment variable ACL_QSH_COMPILE_CMD can be used to replace default quartus compile command (internal use only).

  open($ftemp, '>', $temp_hashed_file) or die "Could not open file $!";
  print $ftemp "$quartus_version\n$synthesize_cmd\n$acl_qsh_compile_cmd\n";
  close $ftemp;

  $before_quartus.= `$hash_exe \"$temp_hashed_file\"`; # Quartus input args hash
  $before_quartus.= `$hash_exe -d \"$acl_board_hw_path\"`; # All bsp directory hash
  $before_quartus.= `$hash_exe -d \"$work_dir\" --filter .v --filter .sv --filter .hdl --filter .vhdl`; # HDL files hash

  unlink $temp_hashed_file;
  save_pkg_section($pkg,'.acl.quartus_input_hash',$before_quartus);
  chdir $starting_dir or mydie("Can't change back into directory $starting_dir: $!"); # Changing back to the dir I started with.
}

sub main {
  my $all_aoc_args="@ARGV";
  my @args = (); # regular args.
  @user_opencl_args = ();
  my $atleastoneflag=0;
  my $dirbase=undef;
  my $board_variant=undef;
  my $using_default_board = 0;
  if (!@ARGV) {
    push @ARGV, qw(--help);
  }
  while (@ARGV) {
    my $arg = shift @ARGV;
    if ( ($arg eq '-h') or ($arg eq '--help') ) { usage(); exit 0; }
    elsif ( ($arg eq '--powerhelp') ) { powerusage(); exit 0; }
    elsif ( ($arg eq '--version') or ($arg eq '-V') ) { version(\*STDOUT); exit 0; }
    elsif ( ($arg eq '-v') ) { $verbose += 1; if ($verbose > 1) {$prog = "#$prog";} }
    elsif ( ($arg eq '--hw') ) { $run_quartus = 1;}
    elsif ( ($arg eq '--quartus') ) { $skip_qsys = 1; $run_quartus = 1;}
    elsif ( ($arg eq '-d') ) { $debug = 1;}
    elsif ( ($arg eq '-s') ) {$simulation_mode = 1; $ip_gen_only = 1; $atleastoneflag = 1;}
    elsif ( ($arg eq '--high-effort') ) { $high_effort = 1; }
    elsif ( ($arg eq '--report') ) { $report = 1; }
    elsif ( ($arg eq '-g') ) {  $dash_g = 1; $user_dash_g = 1; }
    elsif ( ($arg eq '-g0') ) {  $dash_g = 0; }
    elsif ( ($arg eq '--profile') ) {
      $profile = 1;
      $save_last_bc=1
    }
    elsif ( ($arg eq '--save-extra') ) { $pkg_save_extra = 1; }
    elsif ( ($arg eq '--no-env-check') ) { $do_env_check = 0; }
    elsif ( ($arg eq '--no-auto-migrate') ) { $no_automigrate = 1;}
    elsif ( ($arg eq '--initial-dir') ) {
      $#ARGV >= 0 or mydie("Option --initial-dir requires an argument");
      $force_initial_dir = shift @ARGV;
    }
    elsif ( ($arg eq '-o') ) {
      # Absorb -o argument, and don't pass it down to Clang
      $#ARGV >= 0 or mydie("Option $arg requires a file argument.");
      $output_file = shift @ARGV;
      $output_file_arg = $output_file;
    }
    elsif ( ($arg eq '--hash') ) {
      $#ARGV >= 0 or mydie("Option --hash requires an argument");
      $program_hash = shift @ARGV;
    }
    elsif ( ($arg eq '--clang-arg') ) {
      $#ARGV >= 0 or mydie("Option --clang-arg requires an argument");
      # Just push onto @args!
      push @args, shift @ARGV;
    }
    elsif ( ($arg eq '--opt-arg') ) {
      $#ARGV >= 0 or mydie("Option --opt-arg requires an argument");
      $opt_arg_after .= " ".(shift @ARGV);
    }
    elsif ( ($arg eq '--one-pass') ) {
      $#ARGV >= 0 or mydie("Option --one-pass requires an argument");
      $dft_opt_passes = " ".(shift @ARGV);
      $opt_only = 1;
    }
    elsif ( ($arg eq '--llc-arg') ) {
      $#ARGV >= 0 or mydie("Option --llc-arg requires an argument");
      $llc_arg_after .= " ".(shift @ARGV);
    }
    elsif ( ($arg eq '--optllc-arg') ) {
      $#ARGV >= 0 or mydie("Option --optllc-arg requires an argument");
      my $optllc_arg = (shift @ARGV);
      $opt_arg_after .= " ".$optllc_arg;
      $llc_arg_after .= " ".$optllc_arg;
    }
    elsif ( ($arg eq '--sysinteg-arg') ) {
      $#ARGV >= 0 or mydie("Option --sysinteg-arg requires an argument");
      $sysinteg_arg_after .= " ".(shift @ARGV);
    }
    elsif ( ($arg eq '--c-acceleration') ) { $c_acceleration = 1; }
    elsif ( ($arg eq '--parse-only') ) { $parse_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--opt-only') ) { $opt_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--v-only') ) { $verilog_gen_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--ip-only') ) { $ip_gen_only = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '--dump-csr') ) {
      $llc_arg_after .= ' -csr';
    }
    elsif ( ($arg eq '--skip-qsys') ) { $skip_qsys = 1; $atleastoneflag = 1; }
    elsif ( ($arg eq '-c') ) { $compile_step = 1; $atleastoneflag = 1; } # dummy to support -c flow 
    elsif ( ($arg eq '--dis') ) { $disassemble = 1; }
    elsif ( ($arg eq '--tidy') ) { $tidy = 1; }
    elsif ( ($arg eq '--save-temps') ) { $save_temps = 1; }
    elsif ( ($arg eq '--use-ip-library') ) { $use_ip_library = 1; }
    elsif ( ($arg eq '--no-link-ip-library') ) { $use_ip_library = 0; }
    elsif ( ($arg eq '--regtest_mode') ) { $regtest_mode = 1; }
    elsif ( ($arg eq '--fmax') ) {
      $opt_arg_after .= ' -scheduler-fmax=';
      $llc_arg_after .= ' -scheduler-fmax=';
      my $fmax_constraint = (shift @ARGV);
      $opt_arg_after .= $fmax_constraint;
      $llc_arg_after .= $fmax_constraint;
    }
    elsif ( ($arg eq '--seed') ) {
      $#ARGV >= 0 or mydie("Option --seed requires an argument");
      $fit_seed = (shift @ARGV);
    }
    elsif ( ($arg eq '--no-lms') ) {
      $opt_arg_after .= " ".$lmem_disable_split_flag;
    }
    # temporary fix to match broke documentation
    elsif ( ($arg eq '--fp-relaxed') ) {
      $opt_arg_after .= " -fp-relaxed=true";
    }
    # enable sharing flow
    elsif ( ($arg eq '-Os') ) {
       $opt_arg_after .= ' -opt-area=true';
       $llc_arg_after .= ' -opt-area=true';
    }
    # temporary fix to match broke documentation
    elsif ( ($arg eq '--fpc') ) {
      $opt_arg_after .= " -fpc=true";
    }
    elsif ($arg eq '--const-cache-bytes') {
      $sysinteg_arg_after .= ' --cic-const-cache-bytes ';
      $opt_arg_after .= ' --cic-const-cache-bytes=';
      $#ARGV >= 0 or mydie("Option --const-cache-bytes requires an argument");
      my $const_cache_size = (shift @ARGV);
      my $actual_const_cache_size = 16384;
      while ($actual_const_cache_size < $const_cache_size ) {
        $actual_const_cache_size = $actual_const_cache_size * 2;
      }
      $sysinteg_arg_after .= " ".$actual_const_cache_size;
      $opt_arg_after .= $actual_const_cache_size;
    }
    elsif ($arg eq '--board') {
      ($board_variant) = (shift @ARGV);
    }
    elsif ($arg eq '--efi-spec') {
      $#ARGV >= 0 or mydie("Option --efi-spec requires a path/filename");
      !defined $efispec_file or mydie("Too many EFI Spec files provided\n");
      $efispec_file = (shift @ARGV);
    }
    # -Iinc syntax falls through to default below (even if first letter of inc id ' '
    elsif ($arg eq  '-I') { 
        ($#ARGV >= 0 && $ARGV[0] !~ m/^-./) or mydie("Option $arg requires a name argument.");
        push  @args, $arg.(shift @ARGV);
    }
    # library path. Can be invoked either as '-L<path>' or as '-L <path>'
    elsif ($arg =~ m!^-L(\S+)!) {
      push (@lib_paths, $1);
    }
    elsif ($arg eq '-L') {
      $#ARGV >= 0 or mydie("Option -L requires a directory name");
      push (@lib_paths, (shift @ARGV));
    }
    # library name. Can be invoked either as '-L<libname>' or as '-L <libname>'
    elsif ($arg =~ m!^-l(\S+)!) {
      push (@lib_files, $1);
    }
    elsif ($arg eq '-l') {
      $#ARGV >= 0 or mydie("Option -l requires a path/filename");
      push (@lib_files, (shift @ARGV));
    }
    elsif ($arg eq '--library-debug') {
      $opt_arg_after .= ' -debug-only=libmanager';
      $library_debug = 1;
    }
    elsif ($arg eq '-shared') {  
      $created_shared_aoco = 1;
      $compile_step = 1; # '-shared' implies '-c'
      $atleastoneflag = 1;
      # Enabling -g causes problems when compiling resulting
      # library for emulator (crash in 2nd clang invocation due
      # to debug info inconsistencies). Disabling for now.
      #push @args, '-g'; #  '-shared' implies '-g'
      
      # By default, when parsing OpenCL files, clang will mark every
      # non-kernel function as static. This option prevents this.
      push @args, '-dont-make-opencl-functions-static';
    }
    elsif ($arg eq '--profile-config') {
      $#ARGV >= 0 or mydie("Option --profile-config requires a path/filename");
      !defined $profilerconf_file or mydie("Too many profiler config files provided\n");
      $profilerconf_file = (shift @ARGV);
    }
    elsif ($arg eq '--list-boards') {
      list_boards();
      exit 0;
    }
    elsif ($arg eq '--vfabric' || $arg eq '-march=prototype') {
      $vfabric_flow = 1;
      print "$prog: Warning: Rapid Prototyping has been deprecated\n";
    }
    elsif ($arg eq '--grif') {
      $griffin_flow = 1;
    }
    elsif ($arg eq '--create-template') {
      $generate_vfabric = 1;
    }
    elsif ($arg eq '--reuse-existing-templates') {
      $reuse_vfabrics = 1;
    }
    elsif ($arg eq '--template-seed') {
      $#ARGV >= 0 or mydie("Option --template-seed requires an argument");
      $vfabric_seed = (shift @ARGV);
    }
    elsif ($arg eq '--template-library-path') {
      $#ARGV >= 0 or mydie("Option --template-library-path requires an argument");
      $custom_vfab_lib_path = (shift @ARGV);
    }
    elsif ($arg eq '--ggdb' || $arg eq '-march=emulator' ) {
      $emulator_flow = 1;
      if ($arg eq '--ggdb') {
        $dash_g = 1;
      }
    }
    elsif ($arg eq '--soft-ip-c') {
      $#ARGV >= 0 or mydie("Option --soft-ip-c requires a function name");
      $soft_ip_c_name = (shift @ARGV);
      $soft_ip_c_flow = 1;
      $verilog_gen_only = 1;
      $dotfiles = 1;
      print "Running soft IP C flow on function $soft_ip_c_name\n";
    }
    elsif ($arg eq '--accel') {
      $#ARGV >= 0 or mydie("Option --accel requires a function name");
      $accel_name = (shift @ARGV);
      $accel_gen_flow = 1;
      $llc_arg_after .= ' -csr';
      $compile_step = 1;
      $atleastoneflag = 1;
      $sysinteg_arg_after .= ' --no-opencl-system';
    }
    elsif ($arg eq '--device-spec') {
      $#ARGV >= 0 or mydie("Option --device-spec requires a path/filename");
      $device_spec = (shift @ARGV);
    }
    elsif ($arg eq '--dot') {
      $dotfiles = 1;
    }
    elsif ($arg eq '--time') {
      if($#ARGV >= 0 && $ARGV[0] !~ m/^-./) {
        $time_log = shift(@ARGV);
      }
      else {
        $time_log = "-"; # Default to stdout.
      }
    }
    elsif ($arg eq '--time-passes') {
      $time_passes = 1;
      $opt_arg_after .= ' --time-passes';
      $llc_arg_after .= ' --time-passes';
      if(!$time_log) {
        $time_log = "-"; # Default to stdout.
      }
    }
    # Temporary test flag to enable Unified Netlist flow.
    elsif ($arg eq '--un') {
      $opt_arg_after .= ' --un-flow';
      $llc_arg_after .= ' --un-flow';
    }
    elsif ($arg eq '--no-interleaving')  {
      $#ARGV >= 0 or mydie("Option --no-interleaving requires a memory name or 'default'");
      if($ARGV[0] ne 'default' ) {
        $sysinteg_arg_after .= ' --no-interleaving '.(shift @ARGV);
      }
      else {
        #non-heterogeneous sw-dimm-partition behaviour
        #this will target the default memory
        shift(@ARGV);
        $sysinteg_arg_after .= ' --cic-global_no_interleave ';
      }
    }   
    elsif ($arg eq '--global-tree')  {
       $sysinteg_arg_after .= ' --global-tree';
    } 
    elsif ($arg eq '--duplicate-ring')  {
       $sysinteg_arg_after .= ' --duplicate-ring';
    } 
    elsif ($arg eq '--num-reorder')  {
       $sysinteg_arg_after .= ' --num-reorder '.(shift @ARGV);
    }
    elsif ( process_meta_args ($arg, \@ARGV) ) { }
    elsif ( $arg =~ m/\.cl$|\.c$|\.aoco|\.xml/ ) {
      push @given_input_files, $arg;
    }
    elsif ( $arg =~ m/\.aoclib/ ) {
      mydie("Library file $arg specified without -l option");
    }
    elsif ( $arg eq '--big-endian'){ 
      mydie("Big endian generation mode not supported");
    }
    elsif ($arg eq '--dsploc') {
      $#ARGV >= 0 or mydie("Option --dsploc requires an argument");
      $dsploc = (shift @ARGV);
    }
    elsif ($arg eq '--ramloc') {
      $#ARGV >= 0 or mydie("Option --ramloc requires an argument");
      $ramloc = (shift @ARGV);
    }
      else {
      push @args, $arg
    }
  }

  # Don't add -g to user_opencl_args because -g is now enabled by default.
  # Instead add -g0 if the user explicitly disables debug info.
  push @user_opencl_args, @args;
  if (!$dash_g) {
    push @user_opencl_args, '-g0';
  }

  # Propagate -g to clang, opt, and llc
  if ($dash_g || $profile) {
    if ($emulator_flow && ($emulator_arch eq 'windows64')){
      print "$prog: Debug symbols are not supported in emulation mode on Windows, ignoring -g.\n" if $user_dash_g;
    } elsif ($created_shared_aoco) {
      print "$prog: Debug symbols are not supported for shared object files, ignoring -g.\n" if $user_dash_g;
    } else {
      push @args, '-g';
    }
    $opt_arg_after .= ' -dbg-info-enabled';
    $llc_arg_after.= ' -dbg-info-enabled';
  }

  # if no board variant was given by the --board option fall back to the default board
  if (!defined $board_variant) {
    ($board_variant) = acl::Env::board_hardware_default();
    $using_default_board = 1;
  }
  # treat EmulatorDevice as undefined so we get a valid board
  if ($board_variant eq $emulatorDevice ) {
    ($board_variant) = acl::Env::board_hardware_default();
  }

  @user_clang_args = @args;

  if ($regtest_mode){
      $dotfiles = 1;
      $save_temps = 1;
      $report = 1;
      $sysinteg_arg_after .= ' --regtest_mode ';
  }

  if ($dotfiles) {
    $opt_arg_after .= ' --dump-dot ';
    $llc_arg_after .= ' --dump-dot ';
    $sysinteg_arg_after .= ' --dump-dot ';
  }

  $orig_dir = acl::File::abs_path('.');
  $force_initial_dir = acl::File::abs_path( $force_initial_dir || '.' );

  # get the absolute path for the EFI Spec file
  if(defined $efispec_file) {
      chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");
      -f $efispec_file or mydie("Invalid EFI Spec file $efispec_file: $!");
      $absolute_efispec_file = acl::File::abs_path($efispec_file);
      -f $absolute_efispec_file or mydie("Internal error. Can't determine absolute path for $efispec_file");
      chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
  }
  
  # Resolve library args to absolute paths
  if($#lib_files > -1) {
     if ($verbose or $library_debug) { print "Resolving library filenames to full paths\n"; }
     foreach my $libpath (@lib_paths, ".") {
        if (not defined $libpath) { next; }
        if ($verbose or $library_debug) { print "  lib_path = $libpath\n"; }
        
        chdir $libpath or next;
          for (my $i=0; $i <= $#lib_files; $i++) {
             my $libfile = $lib_files[$i];
             if (not defined $libfile) { next; }
             if ($verbose or $library_debug) { print "    lib_file = $libfile\n"; }
             if (-f $libfile) {
               my $abs_libfile = acl::File::abs_path($libfile);
               if ($verbose or $library_debug) { print "Resolved $libfile to $abs_libfile\n"; }
               push (@resolved_lib_files, $abs_libfile);
               # Remove $libfile from @lib_files
               splice (@lib_files, $i, 1);
               $i--;
             }
          }
        chdir $orig_dir;
     }
     
     # Make sure resolved all lib files
     if ($#lib_files > -1) {
        mydie ("Cannot find the following specified library files: " . join (' ', @lib_files));
     }
  }

  # User may have specified multiple input files, either directly or via libraries.
  # Merge them into one to present to compiler.
  my ($input_file, $base) = process_input_file_arguments();
  my $suffix = $base;
  $suffix =~ s/.*\.//;
  $base=~ s/\.$suffix//;
  $base =~ s/[^a-z0-9_]/_/ig;

  if ( $suffix =~ m/^cl$|^c$/ ) {
    $srcfile = $input_file;
    $objfile = $base.".aoco";
    $x_file = $base.".aocx";
    $dirbase = $base;
  } elsif ( $suffix =~ m/^aoco$/ ) {
    $run_quartus = 1;
    $srcfile = undef;
    $objfile = $base.".aoco";
    $x_file = $base.".aocx";
    $dirbase = $base;
  } elsif ( $suffix =~ m/^xml$/ ) {
    # xml suffix is for packaging RTL components into aoco files, to be
    # included into libraries later.
    # The flow is the same as for "aoc -shared -c" for OpenCL components
    # but currently handled by "aocl-libedit" executable
    $hdl_comp_pkg_flow = 1;
    $run_quartus = 0;
    $compile_step = 1;
    $srcfile = $input_file;
    $objfile = $base.".aoco";
    $x_file = $base.".aocx";
    $dirbase = $base;
  } else {
    mydie("No recognized input file format on the command line");
  }    

  # Process $time_log. If defined, then treat it as a file name 
  # (including "-", which is stdout).
  if ($time_log) {
    my $fh;
    if ($time_log ne "-") {
      # If this is an initial run, clobber time_log, otherwise append to it.
      if (not $run_quartus) {
        open ($fh, '>', $time_log) or mydie ("Couldn't open $time_log for time output.");
      } else {
        open ($fh, '>>', $time_log) or mydie ("Couldn't open $time_log for time output.");
      }
    }
    else {
      # Use STDOUT.
      open ($fh, '>&', \*STDOUT) or mydie ("Couldn't open stdout for time output.");
    }

    # From this forward forward, $time_log is now a file handle!
    $time_log = $fh;
  }

  if ( $output_file ) {
    my $outsuffix = $output_file;
    $outsuffix =~ s/.*\.//;
    # Did not find a suffix. Use default for option.
    if ($outsuffix ne "aocx" && $outsuffix ne "aoco") {
      if ($compile_step == 0) {
        $outsuffix = "aocx";
      } else {
        $outsuffix = "aoco";
      }
      $output_file .= "."  . $outsuffix;
    }
    my $outbase = $output_file;
    $outbase =~ s/\.$outsuffix//;
    if ($outsuffix eq "aoco") {
      ($run_quartus == 0 && $compile_step != 0) or mydie("Option -o argument cannot end in .aoco when used to name final output"); 
      $objfile = $outbase.".".$outsuffix;
      $dirbase = $outbase;
      $x_file = undef;
    } elsif ($outsuffix eq "aocx") {
      $compile_step == 0 or mydie("Option -o argument cannot end in .aocx when used with -c");  
      # There are two scenarios where aocx can be used:
      # 1. Input is a AOCO
      # 2. Input is a source file
      #
      # If the input is a AOCO, then $objfile and $dirbase is already set correctly.
      # If the input is a source file, set $objfile and $dirbase based on the AOCX name.
      if ($suffix ne "aoco") {
        $objfile = $outbase . ".aoco";
        $dirbase = $outbase;
      }
      $x_file = $output_file;
    } elsif ($compile_step == 0) {
      mydie("Option -o argument must be a filename ending in .aocx when used to name final output");
    } else {
      mydie("Option -o argument must be a filename ending in .aoco when used with -c");
    }
    $output_file = acl::File::abs_path( $output_file );
  }
  $objfile = acl::File::abs_path( $objfile );
  $x_file = acl::File::abs_path( $x_file );

  if ($srcfile){ # not necesaarily set for "aoc file.aoco" 
    chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");
    -f $srcfile or mydie("Invalid kernel file $srcfile: $!");
    $absolute_srcfile = acl::File::abs_path($srcfile);
    -f $absolute_srcfile or mydie("Internal error. Can't determine absolute path for $srcfile");
    chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
  }

  # get the absolute path for the Profiler Config file
  if(defined $profilerconf_file) {
      chdir $force_initial_dir or mydie("Can't change into dir $force_initial_dir: $!\n");
      -f $profilerconf_file or mydie("Invalid profiler config file $profilerconf_file: $!");
      $absolute_profilerconf_file = acl::File::abs_path($profilerconf_file);
      -f $absolute_profilerconf_file or mydie("Internal error. Can't determine absolute path for $profilerconf_file");
      chdir $orig_dir or mydie("Can't change into dir $orig_dir: $!\n");
  }
  
  # Output file must be defined for this flow
  if ($hdl_comp_pkg_flow) {
    defined $output_file or mydie("Output file must be specified with -o for HDL component packaging step.\n");
  }
  if ($created_shared_aoco and $emulator_flow) {
    mydie("-shared is not compatible with emulator flow.");
  }

  # Can't do multiple flows at the same time
  if ($soft_ip_c_flow + $compile_step + $run_quartus >1) {
      mydie("Cannot have more than one of -c, --soft-ip-c --hw on the command line,\n cannot combine -c with *.aoco either\n");
  }

  # Griffin exclusion until we add further support
  # Some of these (like emulator) should probably be relaxed, even today
  if($griffin_flow == 1 && $vfabric_flow == 1){
    mydie("Griffin flow not compatible with virtual fabric target");
  }
  if($griffin_flow == 1 && $soft_ip_c_flow == 1){
    mydie("Griffin flow not compatible with soft-ip flow");
  }
  if($griffin_flow == 1 && $accel_gen_flow == 1){
    mydie("Griffin flow not compatible with C acceleration");
  }

  # Check that this a valid board directory by checking for a board_spec.xml 
  # file in the board directory.
  if (not $run_quartus) {
    my $board_xml = get_acl_board_hw_path($board_variant)."/board_spec.xml";
    if (!-f $board_xml) {
      print "Board '$board_variant' not found.\n";
      my $board_path = acl::Board_env::get_board_path();
      print "Searched in the board package at: \n  $board_path\n";
      list_boards();
      print "If you are using a 3rd party board, please ensure:\n";
      print "  1) The board package is installed (contact your 3rd party vendor)\n";
      print "  2) You have set the environment variable 'AOCL_BOARD_PACKAGE_ROOT'\n";
      print "     to the path to your board package installation\n";
      mydie("No board_spec.xml found for board '$board_variant' (Searched for: $board_xml).");
    }
  }

  $work_dir = acl::File::abs_path("./$dirbase");

  check_env($board_variant) if $do_env_check;

  if (not $run_quartus) {
    if(!$atleastoneflag && $verbose) {
      print "You are now compiling the full flow!!\n";
    }
    create_system ($base, $work_dir, $srcfile, $objfile, $board_variant, $using_default_board, $all_aoc_args);
  }
  if (not ($compile_step|| $parse_only || $opt_only || $verilog_gen_only)) {
    compile_design ($base, $work_dir, $objfile, $x_file, $board_variant, $all_aoc_args);
  }

  if ($time_log) {
    close ($time_log);
  }
}

main();
exit 0;
# vim: set ts=2 sw=2 expandtab
