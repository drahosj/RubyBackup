require './rbb'

server do
  hostname "drahos.me"
  user "jake"
  destroot "/mnt/backup"
  metaroot "/test/.backup-meta"
  
  file "/test/baddir/stuff/individual.h"
  
  directory "/test/", blacklist: /(baddir|wldir|\.iso$|\.backup-meta)/
  directory "/test/dir1", blacklist: /\.iso$/
  directory "/test/wldir", whitelist: /\.tar\.gz$/
end

run