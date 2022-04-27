#!/usr/bin/env sh
mkdir -p example/ortfo
bundle exec ruby main.rb "version: 0.1.0-alpha.2" example/debian.fsorg --root $(realpath example/ortfo)

# dpkg-deb --build ortfo
# rm -r ortfo
