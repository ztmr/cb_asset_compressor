# ChicagoBoss Asset Compressor
The goal is to create an Erlang/ChicagoBoss alternative
of Django-Compressor plugin.
At the moment, it's in a highly experimental proof-of-concept
phase.

## Current features
* we read all the external links to CSS and JavaScript, minify
  them and include the result back into the original HTML tree;
* such an external link can be either local or remote HTTP(s);
* we skip scripts where we're not sure if it is JavaScript or
  anything else (based on `@type` attribute, external file extension
  and MIME machinery).

## TODO
* integration with ErlyDTL/ChicagoBoss itself;
* no support for CSS minification yet (it's actually passed out
  exactly as it came into the compressor on input);
* at the moment, we only substitute all the asset tags we
  get from the HTML parser. This should be changed to accumulate
  all the JavaScripts and CSS into the buffer which will be
  dumped to an external file. Such a file will be then referenced
  from the main HTML tree -- one reference for JS, one for CSS.
  This is much better and more W3C validator friendly :)
  (The best practice is to move all the styles and scripts
  outside the HTML, especially to allow browsers to cache them
  separately.)
* write more unit tests to be sure we're correct all the time.

## Notes
* the `jsc:js_min` function family is borrowed from the project
  which I am not able to find even after few hours of Googling.
  So please, if you're author of that function and feel aggrieved,
  just drop me an e-mail!
