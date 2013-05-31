-module (cb_asset_compressor).
-export ([process/1, process/2]).
%-compile (export_all).

-define (MIME_JS_ACCEPT, [?MIME_JS_DEFAULT, <<"text/javascript">>,
                          <<"application/x-javascript">>]).
-define (MIME_JS_DEFAULT, <<"application/javascript">>).

-define (MIME_CSS_ACCEPT, [?MIME_CSS_DEFAULT]).
-define (MIME_CSS_DEFAULT, <<"text/css">>).


process (HtmlBuffer) ->
  %% This should be replaced by `boss_env' calls
  process (HtmlBuffer, [{asset_dir_fs, "priv/static"},
                        {asset_dir_web, "/static"},
                        fetch_remote]).

%% At least `asset_dir_fs' and `asset_dir_web' options must be defined!
process (HtmlBuffer, Options) ->
  T = transform (mochiweb_html:parse (HtmlBuffer), Options),
  concat (lists:flatten (mochiweb_html:to_html (T))).

transform (TagList, Options) when is_list (TagList) ->
  [ transform (T, Options) || T <- TagList, T =/= remove_skip_tag ];
transform ({comment, Content}, _Options) ->
  %% Try to parse commented content.
  %% This is useful because of MSIE conditionals!
  %% XXX: it seems mochiweb_html does not handle this correcly :-(
  %case catch (process (Content, Options)) of
  %  {'EXIT', _} -> {comment, Content};
  %  NewContent  -> {comment, NewContent}
  %end;
  {comment, Content};
%% Handle scripts, try to detect if they're JavaScript and minify such of them
transform ({<<"script">> = Tag, Attribs, Content}, Options) ->
  Src = proplists:get_value (<<"src">>, Attribs),
  SrcExt = filename:extension (Src),
  MimeGuess = case mochiweb_mime:from_extension (SrcExt) of
    X when is_list (X) -> list_to_binary (X);
    _                  -> undefined
  end,
  Type = proplists:get_value (<<"type">>, Attribs, ?MIME_JS_DEFAULT),
  IsJsType = lists:member (Type, ?MIME_JS_ACCEPT) orelse
             lists:member (MimeGuess, ?MIME_JS_ACCEPT),
  case {Src, IsJsType} of
    %% No `src' attribute is defined, process the tag body
    {undefined, true} ->
      {ok, _, NewContent} = jsc:compile (concat (Content)),
      {Tag, Attribs, NewContent};
    %% `src' attribute found as well as the `type' is recognized
    %% as JavaScript -- let's process the external script!
    {WebPath, true} ->
      {ok, RawExtContent} = fetch_web_path (binary_to_list (WebPath), Options),
      {ok, _, NewContent} = jsc:compile (concat ([RawExtContent|Content])),
      {Tag, proplists:delete (<<"src">>, Attribs), NewContent};
    %% Keep it untouched, we're not sure what to do with that script
    _ -> {Tag, Attribs, Content}
  end;
%% Load `link' tags and convert them to `style'
transform ({<<"link">> = Tag, Attribs, Content}, Options) ->
  Href = proplists:get_value (<<"href">>, Attribs),
  IsStyle = <<"stylesheet">> =:= proplists:get_value (<<"rel">>, Attribs, <<"stylesheet">>),
  Type = proplists:get_value (<<"type">>, Attribs, ?MIME_CSS_DEFAULT),
  IsCssType = lists:member (Type, ?MIME_CSS_ACCEPT),
  case {Href, IsStyle orelse IsCssType} of
    %% Ignore, we have no href
    {undefined, _}  ->
      {Tag, Attribs, Content};
    {WebPath, true} ->
      {ok, RawExtContent} = fetch_web_path (binary_to_list (WebPath), Options),
      %{ok, _, NewContent} = cssc:compile (RawExtContent), %% XXX
      NewContent = RawExtContent,
      {<<"style">>, [{<<"type">>, ?MIME_CSS_DEFAULT}], NewContent}
  end;
%% Process embedded CSS
transform ({<<"style">> = Tag, Attribs, Content}, _Options) ->
%  {Tag, Attribs, cssc:compile (Content)};
  {Tag, Attribs, Content};
transform ({Tag, Attribs, Content}, Options) ->
  {Tag, Attribs, transform (Content, Options)}.

%% Fetch asset contents as a binary string.
%%
%% There are three general cases:
%% - relative "hello.world.js"
%% - absolute "/static/scripts/hello.world.js" -> use asset_dir_fs/asset_dir_web
%% - any form of XRI "http://foo/" -> if `fetch_remote'
fetch_web_path (Path, Options) ->
  AssetDirWeb = proplists:get_value (asset_dir_web, Options),
  AssetDirFs = proplists:get_value (asset_dir_fs, Options),
  FetchRemote = proplists:is_defined (fetch_remote, Options),
  AssetDirWebLen = length (AssetDirWeb),
  IsInAssetDir = AssetDirWebLen =:= compare (Path, AssetDirWeb),
  PathTail = lists:nthtail (AssetDirWebLen, Path),
  Ret = fun
          ({ok, Data}) -> {ok, Data};
          (Error)      -> throw (Error)
        end,
  case Path of
    %% Absolute web path, so we expect it to start with `AssetDirWeb'
    "/"++_ when IsInAssetDir       -> Ret (fetch_local_file (AssetDirFs, PathTail));
    %% Remote files (download them if `fetch_remote' option is defined)
    "http://"++_ when FetchRemote  -> Ret (fetch_remote_file (Path));
    "https://"++_ when FetchRemote -> Ret (fetch_remote_file (Path));
    %% All the other cases (relative paths)
    %% We expect it's relative to `AssetDirWeb' since it's not
    %% so usual to have a controller that _occasionally_ serve assets.
    %% Of course, `AssetDirWeb' may be controller/action and all the
    %% assets could be served dynamically then.
    %% In these cases, application developer should consider
    %% use of CB's caching techniques.
    _                              -> Ret (fetch_local_file (AssetDirFs, Path))
  end.

%% Remove leading slash to let filename:join work as we need.
fetch_local_file (AssetDir, [$/|Path]) ->
  fetch_local_file (AssetDir, Path);
fetch_local_file (AssetDir, Path) ->
  File = filename:join (AssetDir, Path),
  case file:read_file (File) of
    {ok, Data} -> {ok, Data};
    Whatever   -> {error, {File, Whatever}}
  end.

fetch_remote_file (Uri) ->
  case ibrowse:send_req (Uri, [], get) of
    {ok, _Code, _Hdrs, Content} -> {ok, list_to_binary (Content)};
    Whatever                    -> Whatever
  end.

%% Imported from `idealib_binary', the part of IDEA Library (not public at the moment)
concat (L) when is_list (L) ->
  concat (lists:reverse (L), <<>>).

concat ([], Acc) -> Acc;
concat (<<>>, Acc) -> Acc;
concat ([H|T], Acc) when is_binary (H) ->
  concat (T, <<H/binary, Acc/binary>>).

%% Imported from `idealib_lists', the part of IDEA Library
compare (S1, S2) -> compare (S1, S2, 0).

compare ([], _, Ctr) -> Ctr;
compare (_, [], Ctr) -> Ctr;
compare ([H1|T1], [H2|T2], Ctr) when H1 =:= H2 ->
  compare (T1, T2, Ctr+1);
compare (_, _, Ctr) -> Ctr.


%% EUnit Tests
-ifdef (TEST).
-include_lib ("eunit/include/eunit.hrl").

run_process (Buffer) ->
  process (Buffer, [{asset_dir_fs,  "test/assets"},
                    {asset_dir_web, "/assets"}]).

common_test () ->
  [ begin
      {ok, [{A, B}]} = file:consult (F),
      ?assertEqual (B, run_process (A))
    end
    || F <- filelib:wildcard ("test/*.testcase") ],
  ok.

-endif.

