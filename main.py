import os
import argparse
import subprocess
from pyfiglet import figlet_format
from fsorgfile import *

FORMAT_HELP = f"""fsorg uses a custom-made markup language for describing directory structures.

{colored('# This line will be ignored (comment)', 'grey')}
root:/path/to/base/directory"""

FORMAT_HELP += colored("""
# if root isn't specified, you will be asked to enter the path.
# You can also specify this path with the -r option*
# The root or base directory indicates where all folders should be created.
# Usually, you would want to set it to ~ (user directory, /home/user-name)
# * The root declaration in the fsorg file supersede the -r option """, 'grey')  # TODO: this should be inverted

FORMAT_HELP += """
Folder_Name {
    SubFolder_Name {
        First
        Another_one
    }
    SubFolder2
    <CompanyName>
}
Folder_Name2

This will ask you to assign a value to <CompanyName>
If you respond "Mx3", these folders will be created:

root/Folder_Name
root/Folder_Name/SubFolder_Name
root/Folder_Name/SubFolder_Name/First
root/Folder_Name/SubFolder_Name/Another_one
root/Folder_Name/SubFolder2
root/Folder_Name/Mx3
root/Folder_Name2

(for simplification, /path/to/base/directory is replace with 'root')

"""



def main(args):


    # Adds .fsorg to the end of the fsorg file path if no file extension is specified
    def auto_add_ext(fspath):
        if not re.match(r'\w+\.\w+$', fspath): fspath += '.fsorg'
        return fspath

    if args.format_help:
        print(FORMAT_HELP)
        return None

    DEBUG = args.debug
    if DEBUG or not args.file:
        FILEPATH = os.path.join(os.getcwd(), 'fsorg.txt')
    elif args.file:
        if type(args.file) is list:
            filein = args.file[0]
        else:
            filein = args.file
        FILEPATH = os.path.normpath(os.path.expanduser(filein))
        FILEPATH = auto_add_ext(FILEPATH)
    else:
        FILEPATH = None

    isfile = os.path.isfile(FILEPATH)
    fspath = FILEPATH

    while not isfile:
        fspath = input("Path of the fsorg file:\n")
        fspath = auto_add_ext(fspath)
        isfile = os.path.isfile(fspath)
    FILEPATH = fspath
    del fspath

    verbose_lv = args.verbosity if not DEBUG else 3
    verbose_lv = 1 if args.hollywood else verbose_lv

    fsorg = FsorgFile(FILEPATH,
                      verbosity=verbose_lv,
                      dry_run=args.dry_run,
                      purge=args.purge,
                      quiet=args.quiet,
                      hollywood=args.hollywood,
                      )
    fsorg.mkroot()
    s, e = fsorg.walk()

    if args.hollywood:
        if randint(0,1):
            cprint("Alright, I've hacked their mainframe and disabled their algorithms.", hackerman=True, color='red')
        else:
            cprint("I'm in.", hackerman=True, color='red')

    if not args.quiet:
        if s: cprint(f'Successfully made {s} director{"ies" if int(s) != 1 else "y"}', 'green', hackerman=args.hollywood)
        if e: cprint(f'Failed to make {e} director{"ies" if int(e) != 1 else "y"}', 'red', hackerman=args.hollywood)

        # no need to show tree if the folders aren't created
        if not args.dry_run:
            if input(f'Show the structure of  {fsorg.root_dir} ?\n>').lower().strip().startswith('y'):
                cmd = ['tree', f'"{fsorg.root_dir}"']
                # if we're on UNIX platforms, we need to add the -d flag to only list directories
                if sys.platform != 'win32': cmd.insert(1, '-d')
                if verbose_lv >= 2:
                    print(f"Executing command {''.join(cmd)}")
                subprocess.call(cmd)

        print(f"""Thanks for using \n{figlet_format('fsorg')}\nSee you on <https://github.com/ewen-lbh> ! :D""")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Makes directories from a fsorg text file')

    parser.add_argument('file', metavar='PATH', type=str, nargs='?',
                        help='Path to the fsorg text file. Defaults to "fsorg.txt" in current working directory.')

    parser.add_argument('-r', '--root', metavar='PATH',
                        help='Use this if you haven\'t declared a root path in your fsorg file')

    parser.add_argument('-v', '--verbosity', metavar='LEVEL', type=int,
                        help='Set verbosity level (0-3). Higher values fall back to 3.')

    parser.add_argument('-H', '--format-help', action='store_true',
                        help='Show help about the format used by fsorg files.')

    parser.add_argument('-d', '--dry-run', action='store_true',
                        help="Don't make directories, but show path that would be created")

    parser.add_argument('-p', '--purge', action='store_true',
                        help='Remove all files and folders from inside the root directory')

    parser.add_argument('-D', '--debug', action='store_true',
                        help='Set verbosity to 3 and use the FILE\'s default value')

    argsgp = parser.add_mutually_exclusive_group()

    argsgp.add_argument('-q', '--quiet', action='store_true',
                        help='Only shows errors.')
    argsgp.add_argument('--hollywood', action='store_true',
                        help='Make the whole thing look like a NCIS hacking scene.')

    main(parser.parse_args())
