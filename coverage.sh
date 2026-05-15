#!/usr/bin/env bash

rm -rf cover_db/
HARNESS_PERL_SWITCHES=-MDevel::Cover prove -r t && (
    cover
    open /Users/david/Documents/checkouts/perlscripts/cover_db/coverage.html
)

