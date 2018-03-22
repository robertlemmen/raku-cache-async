#!/usr/bin/env perl6

use v6;

use lib 'lib';

use Cache::Async;

my $i = 0;

my $cache = Cache::Async.new(producer => sub ($k) { return "$k/$i"; });

$cache.put('X', '??');
say "get for X " ~ await $cache.get("X");
say "get for Y " ~ await $cache.get("Y");

