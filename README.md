<center>
<div align="center">
  <img src="./branding/logo-color.svg" width=100>
  <h1>fsorg</h1>
  <p>A file format to describe and create directory structures</p>
</div>
</center>

## Installation

```console
$ gem install fsorg
```

## Usage

```console
Usage:
    fsorg [options] <filepath>
    fsorg [options] <data> <filepath>

Options:
    -h --help                 Show this screen.
    -v --version              Show version.
    -r --root=ROOT_DIRECTORY  Set the root directory.
```

## fsorg file format

The text file that describes the folder structure to create is written using this format

```
# This is a comment
ROOT /mnt/d/documents/new-organization-root

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

<center><em>example.fsorg</em></center>

Running `fsorg example.fsorg` will create this hierarchy inside `/mnt/d/documents/new-organization-root`:

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

`ROOT` is not the only command available. See #3, until they are documented here.
