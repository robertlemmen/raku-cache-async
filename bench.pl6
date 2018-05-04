#!/usr/bin/env perl6

use lib 'lib';

use Cache::Async;

my $producer = sub ($k) {
        return "r$k"; 
    }


sub measure($name, $num-threads, $num-reps, &func) {
    my $start = now;
    my @threads;
    for ^$num-threads -> $t {
        push @threads, Thread.start(sub { 
#            CATCH {
#                default {
#                    say "Exception: " ~ .payload;
#                }
#            }

            for ^$num-reps -> $i {
                &func("key " ~ ($t * 10 + $i));
            }
        });
    }

    for @threads { .finish }
    my $end = now;
    my $duration = $end - $start;
    my $rate = sprintf("%10.2f", ($num-threads * $num-reps) / $duration);
    $duration = sprintf("%6.3f", $duration);
    say "$name : $num-threads threads, $num-reps each, took $duration s -> $rate rq/s";
}

measure("bare producer  ", 1, 10000, sub ($k) { $producer($k) });
measure("bare producer  ", 4, 10000, sub ($k) { $producer($k) });

my $cache = Cache::Async.new(num-shards => 1, producer => $producer);
measure("unsharded cache", 1, 10000, sub ($k) { await $cache.get($k) });
measure("unsharded cache", 4, 10000, sub ($k) { await $cache.get($k) });

my $scache = Cache::Async.new(num-shards => 8, producer => $producer);
measure("sharded cache  ", 1, 10000, sub ($k) { await $scache.get($k) });
measure("sharded cache  ", 4, 10000, sub ($k) { await $scache.get($k) });
