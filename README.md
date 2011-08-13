Goliath Mongo Postgres Example
------------------------------

This is a simple toy example that accesses both mongo and postgres
through a [Goliath async webserver](https://github.com/postrank-labs/goliath).

Much of the code was lifted and rearranged from these demos:

  - [http_log.rb](https://github.com/postrank-labs/goliath/blob/master/examples/http_log.rb)
  - [auth\_and\_rate_limit.rb](https://github.com/postrank-labs/goliath/blob/master/examples/auth_and_rate_limit.rb)

This version uses:

  - [https://github.com/mperham/em_postgresql](https://github.com/mperham/em_postgresql)
  - postgres-pr
  - activerecord 2.3.5

I have a version of this example running with activerecord-3 and pg here:
  - https://github.com/bruchu/goliath_mongo_pg

# Setup

## Setup Database

This sets up gmp_development with a simple 'partners' table, with a key of "a"

`
% cd bin
`
`
% bash setup_db.sh
`
`
% bundle install
`

## Run server

`
% bundle exec ruby mongo_pg.rb -sv
`

### forwarding example

`
% curl -v 'http://localhost:9000/horoscope?app=a'
`

### missing key example

`
% curl -v 'http://localhost:9000/horoscope?app=b'
`
