import argparse
from fsorg.main import main

def run():
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
                        
    parser.add_argument('-t', '--show-tree', action='store_true',
                        help="Show the tree of the resulting directory structure after creation")

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
