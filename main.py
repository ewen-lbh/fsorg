import os
import argparse
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


def print_tree(path, show_files=False, return_string=False):
    mainstr = list()
    for root, dirs, files in os.walk(path):
        level = root.replace(path, '').count(os.sep)
        indent = ' ' * 4 * level
        mainstr.append(f'{indent}{os.path.basename(root)}/')
        subindent = ' ' * 4 * (level + 1)
        if show_files:
            for f in files:
                mainstr.append(f'{subindent}{f}')
    if return_string:
        return '\n'.join(mainstr)
    else:
        return mainstr


def term_h():
    try:
        columns, rows = os.get_terminal_size(0)
    except OSError:
        try:
            columns, rows = os.get_terminal_size(1)
        except OSError:
            rows = os.getenv('COLUMNS', '80')

    return int(rows)


def main(args):

    DEBUG = args.debug
    if DEBUG:
        FILEPATH = os.path.abspath('~/PycharmProjects/fsorg/fsorg_test.txt')
    elif args.file:
        FILEPATH = os.path.abspath(args.file)
    else:
        FILEPATH = None

    isfile = os.path.isfile(FILEPATH)

    while not isfile:
        fspath = input("Path of the organisation file:\n")
        isfile = os.path.isfile(fspath)
    FILEPATH = fspath
    del fspath

    org_file = FsorgFile(FILEPATH,
                         display_root=colored('ROOT', color='cyan'),
                         verbosity=args.verbosity,
                         dry_run=args.dry_run,
                         purge=args.purge
                        )
    org_file.mkroot()
    s, e = org_file.walk()
    if s: print(f'Successfully made {s} directories')
    if e: print(f'Failed to make {e} directories')

    print(f'Structure of {org_file.root_dir}:')
    tree = print_tree(org_file.root_dir)
    if len(tree) > term_h():
        if input('This will fill the entire screen. Show ? [yn]\n').startswith('y'):
            print(tree)
    else:
        print(tree)


if __name__ == '__main__':
    def print_textfile_h(**_): print("""fsorg text file format:

        [root:<root_path>]
        Folder {
            Subfolder,
            Subfolder
        },
        Folder

    Where Folder and Subfolder are folder names
    """)

    parser = argparse.ArgumentParser(description='Makes directories from a fsorg text file',
                                   )

    parser.add_argument('file', metavar='PATH', type=str, nargs=1,
                        help='Path to the fsorg text file')

    parser.add_argument('-r', '--root', metavar='PATH',
                       help='Use this if you haven\'t declared a root path in your fsorg file')

    parser.add_argument('-v', '--verbosity', metavar='LEVEL', type=int,
                        help='Set verbosity level (0-3). Higher values fall back to 3.')

    # parser.add_argument('-H', '--fsorg-files-help', help='Show help about the format used by fsorg files.', action=print_textfile_h)

    group = parser.add_mutually_exclusive_group()

    group.add_argument('-d', '--dry-run',  action='store_true',
                       help="Don't make directories, but show path that would be created")

    group.add_argument('-D', '--debug', action='store_true',
                        help='Turns on debug mode. With this option, FILE is ignored, and the fsorg path is equal to ./fsorg_test.txt Verbosity level is also set to 3')

    group.add_argument('-q', '--quiet',  action='store_true',
                       help='Only shows errors.')
    group.add_argument('-p', '--purge', action='store_true',
                       help='Remove all files and folders from inside the root directory')

    main(parser.parse_args())
