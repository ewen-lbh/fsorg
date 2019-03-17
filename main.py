import os
import argparse
import subprocess
from pyfiglet import figlet_format
from fsorgfile import FsorgFile

try:
    from termcolor import colored
except ModuleNotFoundError:
    def colored(msg, color):
        cmap = {
            'black': '\033[30m',
            'dark red': '\033[31m',
            'dark green': '\033[32m',
            'dark yellow': '\033[33m',
            'dark blue': '\033[34m',
            'dark magenta': '\033[35m',
            'dark cyan': '\033[36m',
            'grey': '\033[37m',
            'dark grey': '\033[90m',
            'red': '\033[91m',
            'green': '\033[92m',
            'yellow': '\033[93m',
            'blue': '\033[94m',
            'magenta': '\033[95m',
            'cyan': '\033[96m',
            'white': '\033[97m',
        }
        end = '\033[0m'
        return f'{cmap[color]}{msg}{end}'

    def cprint(msg, color):
        print(colored(msg, color))

FORMAT_HELP = """ fsorg uses a custom-made markup language for describing directory structures.

# This line will be ignored (comment)
root:/path/to/base/directory

# if root isn't specified, you will be asked to enter the path.
# You can also specify this path with the -r option*
# The root or base directory indicates where all folders should be created.
# Usually, you would want to set it to ~ (user directory, /home/user-name)
# * The root declaration in the fsorg file supersede the -r option """  # TODO: this should be inverted

FORMAT_HELP += """Folder_Name {
    SubFolder_Name {
        First
        Another_one
    }
    SubFolder2
}
Folder_Name2

This will create these folders (for simplification, /path/to/base/directory is replace with 'root':

root/Folder_Name
root/Folder_Name/SubFolder_Name
root/Folder_Name/SubFolder_Name/First
root/Folder_Name/SubFolder_Name/Another_one
root/Folder_Name/SubFolder2
root/Folder_Name2

"""



def main(args):

    if args.format_help:
        print(FORMAT_HELP)

    DEBUG = args.debug
    if DEBUG:
        FILEPATH = os.path.abspath('./fsorg_test.txt')
    elif args.file:
        if type(args.file) is list:
            filein = args.file[0]
        else:
            filein = args.file
        FILEPATH = os.path.normpath(os.path.expanduser(filein))
    else:
        FILEPATH = None

    isfile = os.path.isfile(FILEPATH)
    fspath = FILEPATH

    while not isfile:
        fspath = input("Path of the organisation file:\n")
        isfile = os.path.isfile(fspath)
    FILEPATH = fspath
    del fspath

    fsorg = FsorgFile(FILEPATH,
                      verbosity=args.verbosity,
                      dry_run=args.dry_run,
                      purge=args.purge
                      )
    fsorg.mkroot()
    s, e = fsorg.walk()
    if not args.quiet:
        if s: cprint(f'Successfully made {s} director{"ies" if int(s) != 1 else "y"}', 'green')
        if e: cprint(f'Failed to make {e} director{"ies" if int(e) != 1 else "y"}', 'green')

        if input(f'Show the structure of  {fsorg.root_dir} ?\n>').lower().strip().startswith('y'):
            subprocess.call(['tree', '-d', f'{fsorg.root_dir}'])

        print(f"""Thanks for using \n{figlet_format('fsorg')}\nSee you on <https://github.com/ewen-lbh> ! :D""")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Makes directories from a fsorg text file')

    parser.add_argument('file', metavar='PATH', type=str, nargs=1,
                        help='Path to the fsorg text file')

    parser.add_argument('-r', '--root', metavar='PATH',
                        help='Use this if you haven\'t declared a root path in your fsorg file')

    parser.add_argument('-v', '--verbosity', metavar='LEVEL', type=int,
                        help='Set verbosity level (0-3). Higher values fall back to 3.')

    parser.add_argument('-H', '--format-help', help='Show help about the format used by fsorg files.', action='store_true')

    parser.add_argument('-d', '--dry-run', action='store_true',
                        help="Don't make directories, but show path that would be created")

    parser.add_argument('-p', '--purge', action='store_true',
                        help='Remove all files and folders from inside the root directory')

    argsgp = parser.add_mutually_exclusive_group()

    argsgp.add_argument('-D', '--debug', action='store_true',
                        help='Turns on debug mode. With this option, FILE is ignored, and the fsorg path is equal to ./fsorg_test.txt Verbosity level is also set to 3')

    argsgp.add_argument('-q', '--quiet', action='store_true',
                        help='Only shows errors.')

    main(parser.parse_args())
