#!/usr/bin/env sh
rm -r example/ortfo
mkdir -p example/ortfo
bundle exec fsorg "version: 0.1.0-alpha.2" example/debian.fsorg --root $(realpath example/ortfo) $@

# dpkg-deb --build ortfo
# rm -r ortfo
