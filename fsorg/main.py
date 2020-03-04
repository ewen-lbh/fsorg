import argparse
import webbrowser
import subprocess
from pyfiglet import figlet_format
from fsorg.fsorgfile import *

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
    else:
        FILEPATH = None

    isfile = os.path.isfile(FILEPATH)
    fspath = FILEPATH

    while not isfile:
        fspath = input("Path of the fsorg file:\n")
        isfile = os.path.isfile(fspath)
    FILEPATH = fspath
    del fspath

    if DEBUG:
        verbose_lv = 3
    elif args.hollywood:
        verbose_lv = 1
    elif args.verbosity is not None:
        verbose_lv = args.verbosity
    else:
        verbose_lv = 0

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
        if randint(0, 1):
            cprint("Alright, I've hacked their mainframe and disabled their algorithms.", hackerman=True, color='red')
        else:
            cprint("I'm in.", hackerman=True, color='red')

    if not args.quiet or args.show_tree:
        if s: cprint(f'Successfully made {s} director{"ies" if int(s) != 1 else "y"}', 'green', hackerman=args.hollywood)
        if e: cprint(f'Failed to make {e} director{"ies" if int(e) != 1 else "y"}', 'red', hackerman=args.hollywood)

        # no need to show tree if the folders aren't created
        if not args.dry_run:
            # if we're on UNIX platforms, we need to add the -d flag to only list directories
            is_unix = sys.platform != 'win32'
            if args.show_tree or input(f'Show the structure of {fsorg.root_dir} ?\n>').lower().strip().startswith('y'):
                cmd = f'tree {"-dn" if is_unix else ""} "{fsorg.root_dir}"'
                if verbose_lv >= 2:
                    print(f"Executing command {cmd}")
                subprocess.run(cmd, shell=True)
            if input(f'Open {fsorg.root_dir} ?\n>').lower().strip().startswith('y'):
                webbrowser.open(fsorg.root_dir)

        print(f"""Thanks for using \n{figlet_format('fsorg')}\nSee you on <https://github.com/ewen-lbh> ! :D""")
