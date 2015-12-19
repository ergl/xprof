XProf [![Build Status](https://travis-ci.org/mniec/xprof.svg?branch=master)](https://travis-ci.org/mniec/xprof) [![Coverage Status](https://coveralls.io/repos/mniec/xprof/badge.svg?branch=master&service=github)](https://coveralls.io/github/mniec/xprof?branch=master)
=====

XProf is a profiler that allows you to track execution time of Erlang
functions. It's also able to capture arguments and results of a function calls
that lasted longer than given number of milliseconds.

## Goal

XProf was created to help solving performance problems of live, highly
concurrent and utilized BE systems. It's often the case that high latency or big
CPU usage driven by is caused by very specific requests that are triggering
inefficient code. Finding this code is usually pretty difficult.

## How to use it

![Demo](xprof_demo.gif)

1. Add xprof to your rebar.config (and optionally to reltool.config)
2. Build your project
3. Start xprof by executing `xprof:start()` in Erlang shell
4. Go to http://SERVER:7890
5. Type in function that you would like to start tracing
6. Start tracing clicking green button

```erlang
{deps, [
       ...
       {xprof, ".*", {git, "https://github.com/mniec/xprof.git"}}
]}.
```

## Configuration

You can configure xprof by changing xprof application variables.

Key         | Default     | Description
:-----------|:------------|:-----------
port        |7890         |Port for the web interface

## Contributing

All improvements, fixes and ideas are very welcomed!

Project uses rebar3 for building and testing erlang code. WebUI part resides in
xprof app's priv directory and it's already precompiled so there is no need to
build JS sources in order to run xprof.

### Running tests

```erlang
./rebar3 ct
```

### Working with JS sources

The WebUI uses
* React.js
* ECMAScript 6
* Bootstap
* Bower
* Webpack

All sources are in _priv_ directory. The _app_ folder contains the sources and
the _build_ folder is a placeholder for final JS generated by webpack and then
served by cowboy server (xprof's dependency).

### Starting xprof in dev mode

To develop xprof in convenience following setup is recommended.

In the first terminal window start erlang xprof and _sync_ which automatically
reloads modules that have changed.

```bash
$ export REBAR_PROFILE=dev
$ ./rebar shell
> sync:go().
> xprof:start().
```

In the second window install all the assets and start webpack in development
mode which is also going to recompile all JS files in priv directory when they
are modified.

```bash
$ cd priv;
$ bower install
$ webpack -d
```