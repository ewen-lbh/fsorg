import os
import re
import sys
import time
from random import randint

import rm

# Regex class. (without the [])
LEGAL_FOLDER_CHARS = r'\w_-'
FOLDER_ILLEGAL_CHARS_SUBSTITUTE = '_'

def ansicolors(color='reset'):
    return {
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
    }.get(color, '\033[0m')


def colored(msg, color):
    pre = ansicolors(color)
    end = ansicolors('reset')
    return f'{pre}{msg}{end}'


def typewriter(msg, slowness=0.03, ending_newline=True):
    for i, c in enumerate(list(msg)):
        print(c, end='')
        sys.stdout.flush()
        time.sleep(slowness)
    if ending_newline:
        print('')  # adds back the newline


def cprint(msg, color='reset', hackerman=False, end='\n'):
    if not hackerman:
        print(colored(msg, color), end=end)
    else:
        print(ansicolors(color), end='')
        typewriter(msg, ending_newline=False)
        print(ansicolors(), end=end)


class FsorgFile:
    def __init__(self, filepath, **kwargs):
        self.purge_root = kwargs.get('purge', False)
        self.dry_run = kwargs.get('dry_run', False)
        self.quiet = kwargs.get('quiet', False)
        self.hollywood = kwargs.get('hollywood', False)
        self.debug_level = kwargs.get('verbosity', 0)
        if self.debug_level is None:
            self.debug_level = 0
        self.filepath = filepath
        self.raw = self._raw()
        self.raw_lines = self._lines()
        self.lines = self._placeholders(self._no_coms(self.raw_lines))
        self.root_dir = self._root()
        self.raw_tokens = self._tokenize()
        self.tokens = self._clean_tokens()

        if self.debug_level >= 2:
            cprint(f"FsorgFile filepath set to: \n{self.filepath}", hackerman=self.hollywood)

        if self.debug_level >= 3:
            print("Contents of file (stripped, comments removed):")
            for line in self.lines:
                print(f'     {line}')

        if self.debug_level >= 2:
            print(f"Tokens:")
            for token in self.tokens:
                print(f'     {token}')
            print('')

        if self.dry_run:
            cprint("--- DRY RUN ---\n", "yellow", hackerman=self.hollywood)

        if self.hollywood:
            typewriter(colored("> start counterstrike", "green"), slowness=0.1)

    def _raw(self):
        with open(self.filepath, 'r') as f:
            contents = f.read()
        return contents

    def _lines(self):
        return [line.strip() for line in self.raw.split('\n')]

    def _no_coms(self, lines):
        return [line for line in lines if not re.match(r'^#', line)]

    def _root(self):
        for line in self.lines:
            pattern = r'root:(.+)'
            if re.match(pattern, line):

                root = re.sub(pattern, r'\1', line)
                if root.endswith('/'): root = root[:-1]

                root = os.path.normpath(os.path.expanduser(root))

                if self.debug_level >= 1:
                    cprint(f"Found root directory declaration: {root}", hackerman=self.hollywood)

                return root

        cprint(f"W: No root declaration found in {self.filepath}", 'yellow', hackerman=self.hollywood)
        cprint(f"\tYou can add one using this syntax:\n\troot:path/to/root/directory", hackerman=self.hollywood)
        return False

    def mkroot(self):
        if not self.root_dir: self.root_dir = input("Root directory's path: ")
        if not os.path.isdir(self.root_dir):
            cprint(f"Root directory doesn't exist.", 'yellow', hackerman=self.hollywood)
            cprint(f'Creating root directory {self.root_dir}...', end='', hackerman=self.hollywood)
            os.mkdir(self.root_dir)
            cprint('Done.', 'green')
        else:
            if self.debug_level >= 1:
                cprint(f'Directory {self.root_dir} already exists', 'yellow', hackerman=self.hollywood)

            init_root_sz = len(os.listdir(self.root_dir))
            if init_root_sz > 0:
                cprint(f'W: Directory "{self.root_dir} contains {init_root_sz} files or directories !', 'yellow', hackerman=self.hollywood)

                if self.purge_root:
                    cprint('W: Purging root directory...', hackerman=self.hollywood, end='')
                    for i in os.listdir(self.root_dir):
                        abspath = os.path.join(self.root_dir, i)
                        # subprocess.call(f'rm -rf {abspath}')
                        rm.rm(abspath)
                    cprint('Done.', 'green')

    def _placeholders(self, lines):

        def _is_valid(string):
            if string in ('\n',' '):
                return False
            return True

        def _safe_ask(msg):
            u_in = input(msg)
            while not _is_valid(u_in):
                u_in = input(msg)
            return u_in

        # turns each _ into a space, and title-case the variables
        def _prettify(placeholder_name):
            return placeholder_name.replace('_', ' ').title()

        # copy the lines array
        ret_lines = lines
        # we're going to store placeholders values into a dict,
        # to prevent asking the user to enter a value for a variable
        # more than once
        placeholders = dict()
        # placeholder names can include characters in A-Z, a-z, 0-9 and _
        pattern = r'[^<]*<([\w_]+)>.*'

        # for each line
        for i, line in enumerate(lines):
            # if the line contains a <placeholder>
            if re.match(pattern, line):
                # get placeholder name
                placeholder  = re.sub(pattern, r'\1', line)
                # if we don't have a value for that placeholder yet...
                if placeholder not in placeholders:
                    # ask for it
                    value = _safe_ask(f'<{placeholder}> --> ')
                    # add it to placeholders
                    placeholders[placeholder] = value

                # if this placeholder already has a value (the user already assigned one), simply get it
                else:
                    value = placeholders[placeholder]

                # modify that line in the copied array
                ret_lines[i] = line.replace(f'<{placeholder}>', value)
                if self.debug_level == 1: cprint(f'<{placeholder}> = "{value}"', hackerman=self.hollywood)
                elif self.debug_level >= 2: cprint(f'{line} changed to {ret_lines[i]}', hackerman=self.hollywood)
        return ret_lines


    def repl_vars(self):  # {
        self.lines = self._placeholders(self.lines)
    # }


    def _real_lines(self):
        lines = [line for line in self.lines if not re.match(r'^root:', line) and re.match(rf'[{{}}<>,{LEGAL_FOLDER_CHARS}]', line)]
        return lines

    def _tokenize(self):
        def _string(string):
            tk = ''
            if string[0] in ('{', '}', ',', '\n'):
                return None, string
            for c in string:
                if c not in ('{', '}', ',', '\n'):
                    tk += c
                else:
                    return tk.strip(), string[len(tk):]

        tokens = []
        string = '\n'.join(self._real_lines()) + '\n'  # final '\n' needed, else _string breaks at the last iteration
        while len(string):
            folder, string = _string(string)
            if folder is not None:
                tokens.append(folder)
                continue

            c = string[0]

            if c in ('}', '{', ',', '\n'):
                tokens.append(c)
                string = string[1:]

            elif c in (' ', ''):
                string = string[1:]

            else:
                raise Exception(f"Unexpected character '{c}'")

        return tokens

    @staticmethod
    def sanitize_foldername(foldername):
        return re.sub(rf'[^{LEGAL_FOLDER_CHARS}]', FOLDER_ILLEGAL_CHARS_SUBSTITUTE, foldername)

    def _clean_tokens(self):
        return [tok for tok in self.raw_tokens if tok not in ('', ' ', ',', '\n')]


    def walk(self):
        def isfolder(string):
            return string not in ('{', '}')

        def goback(path):
            newpath = re.sub(rf'([^/]+)/([{LEGAL_FOLDER_CHARS}]+)/?$', r'\1', path)
            return newpath

        if not self.quiet: cprint(f"Using {colored(self.root_dir, 'cyan')} as the base/root directory", hackerman=self.hollywood)
        last_path = self.root_dir + '/'
        successcount = 0
        errcount = 0
        for token in self.tokens:
            if isfolder(token):
                token = self.sanitize_foldername(token)
                if last_path.endswith('/'):
                    last_path += token
                else:
                    last_path = goback(last_path) + '/' + token

                display_path = './' + last_path.replace(self.root_dir + '/', '', 1)

                if self.debug_level or self.dry_run:
                    if not self.quiet:
                        print(f'{colored("mkdir", "dark grey")} {display_path.replace("/", colored("/", "cyan"))}')

                if not os.path.isdir(last_path) and not os.path.isfile(last_path):
                    if not self.dry_run:
                        os.mkdir(last_path)
                    successcount += 1
                else:
                    if self.debug_level or self.dry_run:
                        cprint('E: Directory already exists', 'red')
                    errcount += 1

                if self.debug_level >= 3:
                    print('')
            elif token == '{':
                last_path += '/'
            elif token == '}':
                last_path = goback(last_path)

            if self.hollywood:
                time.sleep(0.1)

        return successcount, errcount
