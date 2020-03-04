# fsorg
Makes directories from a hierarchy-describing text file

## Usage
See the `-h` or `--help` option

## fsorg file format
The text file that describes the folder structure to create is written using this format

    # comment
    root:<path>
    Folder1 {
        Subfolder1
        Subfolder2 {
            Subsubfolder
        }
    }
    Folder2
    Folder3

This will create this hierarchy inside the **\<path\>** folder:

