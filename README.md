# fsorg
Makes directories from a hierarchy-describing text file

## Installation

```console
$ pip install fsorg
```

## Usage
```console
usage: main.py [-h] [-r PATH] [-v LEVEL] [-H] [-d] [-t] [-p] [-D]
               [-q | --hollywood]
               [PATH]

Makes directories from a fsorg text file

positional arguments:
  PATH                  Path to the fsorg text file. Defaults to "fsorg.txt"
                        in current working directory.

optional arguments:
  -h, --help            show this help message and exit
  -r PATH, --root PATH  Use this if you haven't declared a root path in your
                        fsorg file
  -v LEVEL, --verbosity LEVEL
                        Set verbosity level (0-3). Higher values fall back to
                        3.
  -H, --format-help     Show help about the format used by fsorg files.
  -d, --dry-run         Don't make directories, but show path that would be
                        created
  -t, --show-tree       Show the tree of the resulting directory structure
                        after creation
  -p, --purge           Remove all files and folders from inside the root
                        directory
  -D, --debug           Set verbosity to 3 and use the FILE's default value
  -q, --quiet           Only shows errors.
  --hollywood           Make the whole thing look like a NCIS hacking scene.
```

## fsorg file format
The text file that describes the folder structure to create is written using this format

```
# This is a comment
root:/mnt/d/documents/new-organization-root

projects {
	playgrounds
	staging-area
}

resources {
  icons
  samples
  VSTs
  overlays
  textures
  fonts
  logos
  MIDIs
	ISOs
	installers
}

gaming {
  mods {
    minecraft
  }
  graphics {
    minecraft
  }
  shaders {
    minecraft
  }
  maps {
    minecraft
  }
}

music

images {
	gems
  memes {
    oc
    weeb
    dev
    misc
    templates
  }
  screenshots {
    keep
  }
	wallpapers {
		dual-screen
		phone
		wide
	}
}

documents {
  administrative
  cheatsheets
}

installed

installers {
	windows
	linux
}
```

This will create this hierarchy inside `/mnt/d/documents/new-organization-root`:

```
├── documents
│   ├── administrative
│   └── cheatsheets
├── gaming
│   ├── graphics
│   │   └── minecraft
│   ├── maps
│   │   └── minecraft
│   ├── mods
│   │   └── minecraft
│   └── shaders
│       └── minecraft
├── images
│   ├── gems
│   ├── memes
│   │   ├── dev
│   │   ├── misc
│   │   ├── oc
│   │   ├── templates
│   │   └── weeb
│   ├── screenshots
│   │   └── keep
│   └── wallpapers
│       ├── dual-screen
│       ├── phone
│       └── wide
├── installed
├── installers
│   ├── linux
│   └── windows
├── music
├── projects
│   ├── playgrounds
│   └── staging-area
└── resources
    ├── ISOs
    ├── MIDIs
    ├── VSTs
    ├── fonts
    ├── icons
    ├── installers
    ├── logos
    ├── overlays
    ├── samples
    └── textures
```
