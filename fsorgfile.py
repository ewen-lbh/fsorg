import os
import re

import rm

try:
    from termcolor import cprint
except ModuleNotFoundError:
    def cprint(msg, color):
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
        print(f'{cmap[color]}{msg}{end}')


class FsorgFile:
    def __init__(self, filepath, **kwargs):
        self.purge_root = kwargs.get('purge', False)
        self.dry_run = kwargs.get('dry_run', False)
        self.debug_level = kwargs.get('verbosity', 0)
        if self.debug_level is None:
            self.debug_level = 0
        self.filepath = filepath
        self.raw = self._raw()
        self.raw_lines = self._lines()
        self.lines = self._no_coms(self.raw_lines)
        self.root_dir = self._root()
        if not self.root_dir: self.root_dir = input("Root directory's path: ")
        self.raw_tokens = self._tokenize()
        self.tokens = self._clean_tokens()

        if self.debug_level >= 2:
            print(f"FsorgFile filepath set to: \n{self.filepath}")

        if self.debug_level >= 3:
            print("Contents of file (stripped, comments removed):")
            for line in self.lines:
                print(f'     {line}')

        if self.debug_level >= 1:
            print(f"Found root directory declaration: {self.root_dir}")

        if self.debug_level >= 2:
            print(f"Tokens:")
            for token in self.tokens:
                print(f'     {token}')
            print('')

        if self.dry_run:
            print("--- DRY RUN ---\n")

    def _raw(self):
        with open(self.filepath, 'r') as f:
            contents = f.read()
        return contents

    def _lines(self):
        return [line.strip() for line in self.raw.split('\n')]

    def _no_coms(self, lines):
        return [line for line in lines if not re.match(r'^#', line)]

    def _root(self):
        try:
            for line in self.lines:
                pattern = r'root:(.+)'
                if re.match(pattern, line):
                    root = re.sub(pattern, r'\1', line)
            if root.endswith('/'): root = root[:-1]
            return root
        except UnboundLocalError:
            print(f"""W: No root declaration found in {self.filepath}
   You can add one using this syntax:
   root:<path>
   """)
            return False

    def mkroot(self):
        if not os.path.isdir(self.root_dir):
            print(f'Creating root directory {self.root_dir}...', end='')
            os.mkdir(self.root_dir)
            cprint('Done.', 'green')
        else:
            if self.debug_level >= 1:
                cprint(f'Directory {self.root_dir} already exists', 'yellow')

            init_root_sz = len(os.listdir(self.root_dir))
            if init_root_sz > 0:
                cprint(f'W: Directory "{self.root_dir} contains {init_root_sz} files or directories !', 'yellow')

                if self.purge_root:
                    print('W: Purging root directory...', end='')
                    for i in os.listdir(self.root_dir):
                        abspath = os.path.join(self.root_dir, i)
                        # subprocess.call(f'rm -rf {abspath}')
                        rm.rm(abspath)
                    cprint('Done.', 'green')

    def _real_lines(self):
        lines = [line for line in self.lines if not re.match(r'^root:', line) and re.match(r'[{}<>,_\w]', line)]
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
        string = '\n'.join(self._real_lines())+'\n'  # final '\n' needed, else _string breaks and returns None
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

    def _clean_tokens(self):
        return [tok for tok in self.raw_tokens if tok not in ('', ' ', ',', '\n')]

    def walk(self):
        def isfolder(string):
            return string not in ('{', '}')

        def goback(path):
            newpath = re.sub(r'([^/]+)/([\w_]+)/?$', r'\1', path)
            return newpath

        last_path = self.root_dir + '/'
        successcount = 0
        errcount = 0
        for token in self.tokens:
            if isfolder(token):
                if last_path.endswith('/'):
                    last_path += token
                else:
                    last_path = goback(last_path) + '/' + token

                display_path = last_path.replace(self.root_dir+'/', '', 1)

                if self.debug_level or self.dry_run:
                    print(f'{display_path}')

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

        return successcount, errcount
