use Test;

use Cache::Async;

my $cache = Cache::Async.new(producer => 
    sub ($k) { 
        if $k <= 0 {
            die "invalid key";
        } 
        else {
            return "r$k"; 
        }
    });

plan 2;

ok((await $cache.get("1")) eq 'r1', "non-throwing cache get works");
dies-ok({ await $cache.get("0") }, "excpetions get propagated");

done-testing;
