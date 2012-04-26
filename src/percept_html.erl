%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2010. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%

-module(percept_html).
-export([
	page/3, 
	codelocation_page/3, 
        code_page/3,
	databases_page/3, 
	load_database_page/3, 
	processes_page/3, 
        functions_page/3,
	concurrency_page/3,
	process_info_page/3,
        function_info_page/3
	]).

-export([
	value2pid/1, 
	pid2value/1, 
	get_option_value/2,
	join_strings_with/2
	]).

-compile(export_all).

-include("percept.hrl").
-include_lib("kernel/include/file.hrl").

-compile(export_all).
%% API

page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, overview_content(Env, Input)),
    mod_esi:deliver(SessionID, footer()).

processes_page(SessionID, _Env, Input) ->
    io:format("Input:\n~p\n", [Input]),
    Query   = httpd:parse_query(Input),
    io:format("Query:\n~p\n", [Query]),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept_db:select({system, start_ts}),
    TsMin   = percept_analyzer:seconds2ts(Min, StartTs),
    TsMax   = percept_analyzer:seconds2ts(Max, StartTs),
    ProcessTree = percept_db:gen_process_tree(),
    mod_esi:deliver(SessionID, header(mk_display_style(ProcessTree))),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, processes_content(ProcessTree, {TsMin, TsMax})),
    mod_esi:deliver(SessionID, footer()).

functions_page(SessionID, Env, Input) ->
    io:format("Input:\n~p\n", [Input]),
    Query   = httpd:parse_query(Input),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept_db:select({system, start_ts}),
    TsMin   = percept_analyzer:seconds2ts(Min, StartTs),
    TsMax   = percept_analyzer:seconds2ts(Max, StartTs),
    FunCallTree = percept_db:gen_call_tree(),
    mod_esi:deliver(SessionID, header(mk_fun_display_style(FunCallTree))),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, functions_content(Env,{TsMin, TsMax})),
    mod_esi:deliver(SessionID, footer()).

concurrency_page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, concurrency_content(Env, Input)),
    mod_esi:deliver(SessionID, footer()).

databases_page(SessionID, _, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, databases_content()),
    mod_esi:deliver(SessionID, footer()).
    
codelocation_page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, codelocation_content(Env, Input)),
    mod_esi:deliver(SessionID, footer()).

code_page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, code_content(Env, Input)),
    mod_esi:deliver(SessionID, footer()).

process_info_page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, process_info_content(Env, Input)),
    mod_esi:deliver(SessionID, footer()).

function_info_page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, menu(Input)), 
    mod_esi:deliver(SessionID, function_info_content(Env, Input)),
    mod_esi:deliver(SessionID, footer()).

load_database_page(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),

    % Very dynamic page, handled differently
    load_database_content(SessionID, Env, Input),
    mod_esi:deliver(SessionID, footer()).


%%% --------------------------- %%%
%%% 	Content pages		%%%
%%% --------------------------- %%%

overview_content(_Env, Input) ->
    io:format("Input:\n~p\n", [Input]),
    Query = httpd:parse_query(Input),
    Min = get_option_value("range_min", Query),
    Max = get_option_value("range_max", Query),
    Width  = 1200,
    Height = 600,
    TotalProfileTime = ?seconds( percept_db:select({system, stop_ts}), 
    				 percept_db:select({system, start_ts})),
    RegisteredProcs = length(percept_db:select({information, procs})),
    RegisteredPorts = length(percept_db:select({information, ports})), 
    
    InformationTable = 
	"<table>" ++
	table_line(["Profile time:", TotalProfileTime]) ++
        table_line(["Schedulers:", erlang:system_info(schedulers)]) ++
	table_line(["Processes:", RegisteredProcs]) ++
        table_line(["Ports:", RegisteredPorts]) ++
    	table_line(["Min. range:", Min]) ++
    	table_line(["Max. range:", Max]) ++
    	"</table>",
    
    Header = "
    <div id=\"content\">
    <div>" ++ InformationTable ++ "</div>\n
    <form name=form_area method=POST action=/cgi-bin/percept_html/page>
    <input name=data_min type=hidden value=" ++ term2html(float(Min)) ++ ">
    <input name=data_max type=hidden value=" ++ term2html(float(Max)) ++ ">\n",

    
    RangeTable = 
	"<table>"++
	table_line([
	    "Min:", 
	    "<input name=range_min value=" ++ term2html(float(Min)) ++">",
	    "<select name=\"graph_select\" onChange=\"select_image()\">
	      	<option value=\""++ url_graph(Width, Height, Min, Max, []) ++"\" />Ports & Processes
                <option value=\""++ url_sched_graph(Width, Height, Min, Max, []) ++"\" />Schedulers
             </select>",
	    "<input type=submit value=Update>"
	    ]) ++
	table_line([
	    "Max:", 
	    "<input name=range_max value=" ++ term2html(float(Max)) ++">",
	  %%  "",
	    "<a href=/cgi-bin/percept_html/codelocation_page?range_min=" ++
	    term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">Code location </a>",
            "<a href=/cgi-bin/percept_html/code_page?range_min=" ++
	    term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">Code execution</a>"
	    ]) ++
    	"</table>",
   
 
    MainTable = 
	"<table>" ++
	table_line([div_tag_graph()]) ++
	table_line([RangeTable]) ++
	"</table>",

    Footer = "</div></form>",
    
    Header ++ MainTable ++ Footer.

div_tag_graph() ->
	%background:url('/images/loader.gif') no-repeat center;
    "<div id=\"percept_graph\" 
	onMouseDown=\"select_down(event)\" 
	onMouseMove=\"select_move(event)\" 
	onMouseUp=\"select_up(event)\"

	style=\"
	background-size: 100%;
	background-origin: content;
	width: 100%;
	position:relative; 
	\">
	
	<div id=\"percept_areaselect\"
	style=\"background-color:#ef0909;
	position:relative;
	visibility:hidden;
      	border-left: 1px solid #101010;
	border-right: 1px solid #101010;
	z-index:2;
	width:40px;
	height:40px;\"></div></div>".

-spec url_graph(
	Widht :: non_neg_integer(),
	Height :: non_neg_integer(),
	Min :: float(),
	Max :: float(),
	Pids :: [pid()]) -> string().

url_graph(W, H, Min, Max, []) ->
    "/cgi-bin/percept_graph/graph?range_min=" ++ term2html(float(Min)) 
    	++ "&range_max=" ++ term2html(float(Max))
	++ "&width=" ++ term2html(float(W))
	++ "&height=" ++ term2html(float(H)).

url_sched_graph(W, H, Min, Max, []) ->
    "/cgi-bin/percept_graph/scheduler_graph?range_min=" ++ term2html(float(Min)) 
    	++ "&range_max=" ++ term2html(float(Max))
	++ "&width=" ++ term2html(float(W))
	++ "&height=" ++ term2html(float(H)).

%%% process_info_content

process_info_content(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Pid = get_option_value("pid", Query),
    [I] = percept_db:select({information, Pid}),
    ArgumentString = case I#information.entry of
    	{_, _, Arguments} -> lists:flatten( [term2html(Arg) ++ "<br>" || Arg <- Arguments]);
	_                 -> ""
    end,

    TimeTable = html_table([
	[{th, ""}, 
	 {th, "Timestamp"}, 
	 {th, "Profile Time"}],
	[{td, "Start"},
	 term2html(I#information.start),
	 term2html(procstarttime(I#information.start))],
	[{td, "Stop"},
	 term2html(I#information.stop),
	 term2html(procstoptime(I#information.stop))]
	]),   

    InfoTable = html_table([
                            [{th, "Pid"},        term2html(I#information.id)],
                            [{th, "Name"},       term2html(I#information.name)],
                            [{th, "Entrypoint"}, mfa2html(I#information.entry)],
                            [{th, "Arguments"},  ArgumentString],
                            [{th, "Timetable"},  TimeTable],
                            [{th, "Parent"},     pid2html(I#information.parent)],
                            [{th, "Children"},   lists:flatten(lists:map(fun(Child) -> pid2html(Child) ++ " " end, I#information.children))],
                            [{th, "RQ_history"}, term2html(lists:reverse(I#information.rq_history))],
                            [{th, "{#msg_received, <br>  avg_msg_size}"},term2html(info_msg_received(I))],
                            [{th, "{#msg_sent, <br> #msg_sent_to_same_RQ, <br> #msg_sent_to_another_RQ,<br> avg_msg_size}"},  term2html(info_msg_sent(I))]
                           ]),

    PidActivities = percept_db:select({activity, [{id, Pid}]}),
    WaitingMfas   = percept_analyzer:waiting_activities(PidActivities),
    TotalWaitTime = lists:sum( [T || {T, _, _} <- WaitingMfas] ),
    MfaTable = html_table([
        [{th, "percentage"},
         {th, "total"},         
         {th, "mean"},
         {th, "stddev"},
         {th, "#recv"},
         {th, "module:function/arity"}]] ++  [
	[{td, image_string(percentage, [{width, 100}, {height, 10}, {percentage, Time/TotalWaitTime}])},
	 {td, term2html(Time)},
	 {td, term2html(Mean)},
	 {td, term2html(StdDev)},
	 {td, term2html(N)}, 
	 {td, mfa2html(MFA)} ] || {Time, MFA, {Mean, StdDev, N}} <- WaitingMfas]),
   
    "<div id=\"content\">" ++
    InfoTable ++ "<br>" ++
    MfaTable ++
    "</div>".


function_info_content(_Env, Input) ->
    io:format("Info:\n~p\n", [Input]),
    Query = httpd:parse_query(Input),
    io:format("Query:~p\n", [Query]),
    Pid = get_option_value("pid", Query),
    MFA = get_option_value("mfa", Query),
    io:format("Pid:\n~p\n", [Pid]),
    io:format("MFA:\n~p\n", [MFA]),
    [I] = percept_db:select({information, Pid}),
    io:format("I:\n~p\n", [I]),
    io:format("Key:\n~p\n", [{funs, {Pid, MFA}}]),
    [F] = percept_db:select({funs, {Pid, MFA}}),
    io:format("F:\n~p\n", [F]),
    CallersTable = html_table([[{th, " module:function/arity "}, {th, " call count "}]]++
                                  [[{td, mfa2html_with_link({Pid,C})}, {td, term2html(Count)}]||
                                      {C, Count}<-F#fun_info.callers]),
    CalledTable= html_table([[{th, " module:function/arity "}, {th, " call count "}]]++
                                  [[{td, mfa2html_with_link({Pid,C})}, {td, term2html(Count)}]||
                                      {C, Count}<-F#fun_info.called]),
    InfoTable = html_table([
                            [{th, "Pid"},         pid2html(Pid)],
                            [{th, "Entrypoint"},  mfa2html(I#information.entry)],
                            [{th, "M:F/A"},       mfa2html_with_link({Pid, MFA})],
                            [{th, "Call count"},  term2html(lists:sum([element(2, Caller)||
                                                                          Caller<-F#fun_info.callers]))],
                            [{th, "Callers"},     CallersTable], 
                            [{th, "Called"},      CalledTable]
                           ]),
    "<div id=\"content\">" ++
     InfoTable ++ "<br>" ++
         "</div>".

%%% concurrency content
concurrency_content(_Env, Input) ->
    %% Get query
    Query = httpd:parse_query(Input),
    
    %% Collect selected pids and generate id tags
    Pids = [value2pid(PidValue) || {PidValue, Case} <- Query, Case == "on", PidValue /= "select_all"],
    IDs  = [{id, Pid} || Pid <- Pids],

   %%o:format("IDs:\n~p\n", [IDs]),
    % FIXME: A lot of extra work here, redo

    %% Analyze activities and calculate area bounds
    Activities = percept_db:select({activity, IDs}),
    StartTs = percept_db:select({system, start_ts}), 
    Counts = [{Time, Y1 + Y2} || {Time, Y1, Y2} <- percept_analyzer:activities2count2(Activities, StartTs)],
    {T00,_,T10,_} = percept_analyzer:minmax(Counts),
    T0 = T00/1000000,
    T1 = T10/1000000, 
    % FIXME: End
    
    PidValues = [pid2value(Pid) || Pid <- Pids],

    %% Generate activity bar requests
    ActivityBarTable = lists:foldl(
    	fun(Pid, Out) ->
	    ValueString = pid2value(Pid),
	    Out ++ 
	    	table_line([
	    	    pid2html(Pid),
		   "<img onload=\"size_image(this, '" ++ 
		   image_string_head("activity", [{"pid", ValueString}, {range_min, T0},{range_max, T1},{height, 10}], []) ++
		   "')\" src=/images/white.png border=0 />"
		])
	end, [], Pids),

    %% Make pids request string
    PidsRequest = join_strings_with(PidValues, ":"),

    "<div id=\"content\">
    <table cellspacing=0 cellpadding=0 border=0>" ++
    table_line([
    	"",
	"<img onload=\"size_image(this, '" ++ 
	image_string_head("graph", [{"pids", PidsRequest},{range_min, T0}, {range_max, T1}, {height, 400}], []) ++
	"')\" src=/images/white.png border=0 />"
    ]) ++
    ActivityBarTable ++
    "</table></div>\n".

processes_content(ProcessTree, {TsMin, TsMax}) ->
    Ports = percept_db:select({information, ports}),
    SystemStartTS = percept_db:select({system, start_ts}),
    SystemStopTS = percept_db:select({system, stop_ts}),
    ProfileTime = ?seconds(SystemStopTS, SystemStartTS),
    Acts = percept_db:select({activity, [{ts_min, TsMin}, {ts_max, TsMax}]}),
    ActivePids = sets:to_list(sets:from_list([A#activity.id||A<-Acts])),
    ActiveProcsInfo=lists:append([ets:lookup(pdb_info, Pid)||Pid <- ActivePids]),
    ProcsHtml = mk_procs_html(ProcessTree, ProfileTime, ActiveProcsInfo),
    PortsHtml = lists:foldl(
    	fun (I, Out) -> 
	    StartTime = procstarttime(I#information.start),
	    EndTime   = procstoptime(I#information.stop),
	    Prepare = 
	    	table_line([
		    "",
		    pid2html(I#information.id),
		    image_string(proc_lifetime, [
			{profiletime, ProfileTime},
			{start, StartTime},
			{"end", term2html(float(EndTime))},
			{width, 100},
			{height, 10}]),
		    mfa2html(I#information.entry),
		    term2html(I#information.name),
		    pid2html(I#information.parent),
                    integer_to_list(max(0,length(I#information.rq_history)-1)),
                    term2html(info_msg_received(I)),
                    term2html(info_msg_sent(I))
       		]),
		[Prepare|Out]
	end, [], Ports),

    Selector = "<table>" ++
	table_line([
	    "<input onClick='selectall()' type=checkbox name=select_all>Select all"]) ++
	table_line([
	    "<input type=submit value=Compare>"]) ++
    	"</table>",

    if 
	length(ProcsHtml) > 0 ->
	    ProcsHtmlResult = 
	    "<tr><td><b>Processes</b></td></tr>
	    <tr><td>
 	   <table width=900 cellspacing=10 border=0>
		<tr>
		<td align=middle width=40><b>Select</b></td>
                <td align=middle width=40> <b>[+/-]</b></td>
		<td align=middle width=80><b>Pid</b></td>
		<td align=middle width=80><b>Lifetime</b></td>
	        <td align=middle width=80><b>Name</b></td>
		<td align=middle width=80><b>Parent</b></td>
                <td align=middle width=80><b>#RQ_chgs</b></td>
                <td align=middle width=80><b>#msgs_received</b></td>
                <td align=middle width=80><b>#msgs_sent</b></td>
                <td align=middle width=100><b>Entrypoint</b></td>
		</tr>" ++
		lists:flatten(ProcsHtml) ++ 
	    "</table>
	    </td></tr>";
	true ->
	    ProcsHtmlResult = ""
    end,
    if 
	length(PortsHtml) > 0 ->
    	    PortsHtmlResult = " 
	    <tr><td><b>Ports</b></td></tr>
            <table width=900  border=1 cellspacing=10 cellpadding=2>
		<tr>
		<td align=middle width=40><b>Select</b></td>
                <td align=middle width=40> <b>[+/-]</b></td>
		<td align=middle width=80><b>Pid</b></td>
		<td align=middle width=80><b>Lifetime</b></td>
	        <td align=middle width=80><b>Name</b></td>
		<td align=middle width=80><b>Parent</b></td>
                <td align=middle width=80><b>#RQ_chgs</b></td>
                <td align=middle width=80><b>#msgs_received</b></td>
                <td align=middle width=80><b>#msgs_sent</b></td>
                <td align=middle width=100><b>Entrypoint</b></td>
		</tr>" ++
	      lists:flatten(PortsHtml) ++
		"</table>
	    </td></tr>";
	true ->
	    PortsHtmlResult = ""
     end,

    Right = "<div>"
    ++ Selector ++ 
    "</div>\n",

    Middle = "<div id=\"content\">
    <table>" ++
    ProcsHtmlResult ++
    PortsHtmlResult ++ 
    "</table>" ++
    Right ++ 
    "</div>\n",
    
    "<form name=process_select method=POST action=/cgi-bin/percept_html/concurrency_page>" ++
    Middle ++ 
    "</form>".

mk_procs_html(ProcessTree, ProfileTime, ActiveProcsInfo) ->
    lists:foldl(
      fun ({I, Children},Out) ->
              Id=I#information.id,
              StartTime = procstarttime(I#information.start),
              EndTime   = procstoptime(I#information.stop),
              Prepare =
                  table_line([
                              "<input type=checkbox name=" ++ pid2value(I#information.id) ++ ">",
                              expand_or_collapse(Children, Id),
                              case lists:member(I, ActiveProcsInfo) orelse  is_parent(Id, ActiveProcsInfo) of 
                                  true ->pid2html_with_color(I#information.id);
                                  false ->
                                      pid2html(I#information.id)
                              end,
                              image_string(proc_lifetime, [
                                                           {profiletime, ProfileTime},
                                                           {start, StartTime},
                                                           {"end", term2html(float(EndTime))},
                                                           {width, 100},
                                                           {height, 10}]),
                             term2html(I#information.name),
                              pid2html(I#information.parent),
                              integer_to_list(max(0,length(I#information.rq_history)-1)),
                              msg2html(info_msg_received(I)),
                              msg2html(info_msg_sent(I)),
                              mfa2html(I#information.entry)]),
              SubTable = sub_table(Id, Children, ProfileTime, ActiveProcsInfo),
              [Prepare, SubTable|Out]
      end, [], ProcessTree).

functions_content(_Env, _Input) ->
    FunCallTree= percept_db:gen_call_tree(),
    FunsHtml=mk_funs_html(FunCallTree),
    Table=if length(FunsHtml) >0 ->
                  "<table border=1 cellspacing=10 cellpadding=2>
                  <tr>
	          <td align=left width=80><b> Pid </b></td>
                  <td align=left width=80><b> [+/-] </b></td>
		  <td align=right width=160><b> module:function/arity </b></td>
	          <td align=right width=80><b> call count </b></td>                  
	          </tr>" ++
                      lists:flatten(FunsHtml) ++ 
                      "</table>" ;
             true ->
                  ""
          end,
    "<div id=\"content\">" ++ 
        Table ++ 
        "</div>".

mk_funs_html(FunCallTree) ->
    mk_funs_html_1(undefined, FunCallTree).

mk_funs_html_1(Parent, Children) ->
    lists:foldl(
      fun({F, FChildren}, Out) ->
              Id={Pid, _MFA} = F#fun_info.id,
              case lists:keyfind(Parent, 1, F#fun_info.callers) of 
                  {Parent, CNT} -> CNT;
                  false ->
                      CNT = 1,
                      CNT
              end,
              Prepare = 
                  table_line([pid2value(Pid),
                              fun_expand_or_collapse(FChildren, Id),
                              mfa2html_with_link(Id),
                              term2html(CNT)]),
              SubTable = fun_sub_table(Id, FChildren),
              [Prepare, SubTable|Out]
      end, [], lists:reverse(Children)).

fun_sub_table(_Id, []) ->
    "";
fun_sub_table(Id={_Pid, Func},Children) ->
    SubHtml = mk_funs_html_1(Func, Children),
    "<tr><td colspan=\"10\"> <table cellspacing=10  cellpadding=2 border=1 "
        "id=\""++mk_fun_table_id(Id)++"\", style=\"margin-left:60px;\">" ++
        SubHtml ++ "</table></td></tr>".
     %% "<tr><td colspan=\"10\"> <table width=450 cellspacing=10 "
     
id_to_list({Pid, undefined}) ->pid_to_list(Pid)++"undefined";
id_to_list({Pid, {M,F,A}}) ->
    pid_to_list(Pid)++atom_to_list(M)++atom_to_list(F)++integer_to_list(A).


mk_fun_table_id(Id) ->
    "t"++[C||C<-id_to_list(Id), 
             not lists:member(C,[14,36, 45, 46,47, 60, 62,94])].


info_msg_received(I) ->
    {No, Size} = I#information.msgs_received,
    AvgSize = case No of 
                  0 -> 0;
                  _ -> Size div No
              end,
    {No, AvgSize}.


info_msg_sent(I) ->
    {No, SameRq, OtherRqs, Size} = I#information.msgs_sent,
    AvgSize = case No of 
                  0 -> 0;
                  _ -> Size div No
              end,
    {No, SameRq, OtherRqs, AvgSize}.

fun_expand_or_collapse(Children, Id) ->
    case Children of 
        [] ->
            "<input type=\"button\", value=\"-\">";
        _ ->
            "<input type=\"button\" id=\"lnk"++id_to_list(Id)++
                "\" onclick = \"return toggle('lnk"++id_to_list(Id)++"', '"
                ++mk_fun_table_id(Id)++"')\", value=\"+\">"
    end.

expand_or_collapse(Children, Id) ->
    case Children of 
        [] ->
            "<input type=\"button\", value=\"-\">";
        _ ->
            "<input type=\"button\" id=\"lnk"++pid_to_list(Id)++
                "\" onclick = \"return toggle('lnk"++pid_to_list(Id)++"', '"
                ++mk_table_id(Id)++"')\", value=\"+\">"
    end.

mk_table_id(Pid) ->
    "t"++[C||C<-pid_to_list(Pid), not lists:member(C, [46, 60, 62])].

sub_table(_Id, [], _ProfileTime, _) ->
    "";
sub_table(Id, Children, ProfileTime, ActivePids) ->
    SubHtml=mk_procs_html(Children, ProfileTime, ActivePids),
    "<tr><td colspan=\"10\"> <table width=950 cellspacing=10  cellpadding=2 border=1 "
        "id=\""++mk_table_id(Id)++"\", style=\"margin-left:60px;\">" ++
        SubHtml ++ "</table></td></tr>".


mk_fun_display_style(FunCallTree) ->
    Str = parent_funs(FunCallTree),
    "\n<style type=\"text/css\">\n" ++
        Str ++ " {display:none;}\n" ++
        "</style>\n".

parent_funs(FunCallTree) ->
    parent_funs(FunCallTree, []).
parent_funs([], Out) ->
    Out;
parent_funs([F|Fs], Out) ->
    case F of 
        {_, []} ->
            parent_funs(Fs, Out);
        {Fun, Children} ->
            if Out==[] ->
                    parent_funs(Children++Fs, Out++"#"++mk_fun_table_id(Fun#fun_info.id));
               true ->
                    parent_funs(Children++Fs, Out++",#"++mk_fun_table_id(Fun#fun_info.id))
            end
    end.

mk_display_style(ProcessTrees) ->
    Str = parent_pids(ProcessTrees),
    "\n<style type=\"text/css\">\n" ++
      Str ++ " {display:none;}\n" ++
     "</style>\n".


parent_pids(ProcessTrees) ->
    parent_pids(ProcessTrees, []).
parent_pids([], Out) -> Out;
parent_pids([T|Ts], Out) ->
    case T of 
        {_I,[]} ->
            parent_pids(Ts, Out);
        {I, Children} ->
            if Out==[] ->
                    parent_pids(Children++Ts, Out++"#"++mk_table_id(I#information.id));
               true ->
                    parent_pids(Children++Ts, Out++",#"++mk_table_id(I#information.id))
            end
    end.

is_parent(I, ActiveProcsInfo) ->  
    lists:any(fun(P) ->
                      lists:member(I, P#information.ancestors)
              end, ActiveProcsInfo).
  
procstarttime(TS) ->
    case TS of
    	undefined -> 0.0;
	TS -> ?seconds(TS,percept_db:select({system, start_ts}))
    end.

procstoptime(TS) ->
    case TS of
    	undefined -> ?seconds(percept_db:select({system, stop_ts}), 
                              percept_db:select({system, start_ts}));
	TS -> ?seconds(TS, percept_db:select({system, start_ts}))
    end.

databases_content() ->
    "<div id=\"content\">
	<form name=load_percept_file method=post action=/cgi-bin/percept_html/load_database_page>
	<center>
	<table>
	    <tr><td>Enter file to analyse:</td><td><input type=hidden name=path /></td></tr>
	    <tr><td><input type=file name=file size=40 /></td><td><input type=submit value=Load onClick=\"path.value = file.value;\" /></td></tr>
	</table>
	</center>
	</form>
	</div>".

load_database_content(SessionId, _Env, Input) ->
    Query = httpd:parse_query(Input),
    {_,{_,Path}} = lists:keysearch("file", 1, Query),
    {_,{_,File}} = lists:keysearch("path", 1, Query),
    Filename = filename:join(Path, File),
    % Check path/file/filename
    
    mod_esi:deliver(SessionId, "<div id=\"content\">"), 
    case file:read_file_info(Filename) of
	{ok, _} ->
    	    Content = "<center>
    	    Parsing: " ++ Filename ++ "<br>
    	    </center>",
	    mod_esi:deliver(SessionId, Content),
	    case percept:analyze(Filename) of
		{error, Reason} ->
	    	    mod_esi:deliver(SessionId, error_msg("Analyze" ++ term2html(Reason)));
		_ ->
		    Complete = "<center><a href=\"/cgi-bin/percept_html/page\">View</a></center>",
	    	   mod_esi:deliver(SessionId, Complete)
	    end;
	{error, Reason} ->
	    mod_esi:deliver(SessionId, error_msg("File" ++ term2html(Reason)))
    end,
    mod_esi:deliver(SessionId, "</div>"). 

codelocation_content(_Env, Input) ->
    Query   = httpd:parse_query(Input),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept_db:select({system, start_ts}),
    TsMin   = percept_analyzer:seconds2ts(Min, StartTs),
    TsMax   = percept_analyzer:seconds2ts(Max, StartTs),
    Acts    = percept_db:select({activity, [{ts_min, TsMin}, {ts_max, TsMax}]}),
    Secs  = [timer:now_diff(A#activity.timestamp,StartTs)/1000 || A <- Acts],
    Delta = cl_deltas(Secs),
    Zip   = lists:zip(Acts, Delta),
    Table = html_table([
	[{th, "delta [ms]"},
	 {th, "time [ms]"},
	 {th, " pid "},
	 {th, "activity"},
	 {th, "module:function/arity"},
	 {th, "#runnables"}]] ++  [
	[{td, term2html(D)},
	 {td, term2html(timer:now_diff(A#activity.timestamp,StartTs)/1000)},
	 {td,  pid2html(A#activity.id)},
	 {td, term2html(A#activity.state)},
	 {td,  mfa2html(A#activity.where)},
	 {td, term2html(A#activity.runnable_count)}] || {A, D} <- Zip ]),

    "<div id=\"content\">" ++
    Table ++ 
    "</div>".

cl_deltas([])   -> [];
cl_deltas(List) -> cl_deltas(List, [0.0]).
cl_deltas([_], Out)       -> lists:reverse(Out);
cl_deltas([A,B|Ls], Out) -> cl_deltas([B|Ls], [B - A | Out]).


code_content(_Env, Input) ->
    Query   = httpd:parse_query(Input),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept_db:select({system, start_ts}),
    TsMin   = percept_analyzer:seconds2ts(Min, StartTs),
    TsMax   = percept_analyzer:seconds2ts(Max, StartTs),
    ActiveFuns  = percept_db:select({code,[{ts_min, TsMin}, {ts_max, TsMax}]}),
    Table = html_table(
              [[{th, " pid "},
                {th, "module:function/arity"},
                {th, "activity"},
                {th, "function start/end secs"},
                {th, "monitor start/end secs"}]] ++
                   [[{td, pid2html((element(1, F#funcall_info.id)))},
                     {td, term2html(F#funcall_info.func)},
                     {td, make_image_string(F, {Min, Max})},
                     {td, term2html({?seconds(element(2, F#funcall_info.id), StartTs),
                                     ?seconds(F#funcall_info.end_ts, StartTs)})},
                     {td, term2html({Min, Max})}]
                   || F <- ActiveFuns, ?seconds(F#funcall_info.end_ts, element(2, F#funcall_info.id))>0.01]),
    "<div id=\"content\">" ++ 
        Table ++ 
        "</div>".
   


make_image_string(F, {QueryStart, QueryEnd})->
    SystemStartTS = percept_db:select({system, start_ts}),
    FunStart = ?seconds(element(2, F#funcall_info.id), SystemStartTS),
    FunEnd = ?seconds(F#funcall_info.end_ts,SystemStartTS),
    image_string(query_fun_time,
                 [{query_start, QueryStart},
                  {fun_start, FunStart},
                  {query_end, QueryEnd},
                  {fun_end, FunEnd},
                  {width, 100},
                  {height, 10}]).


%%% --------------------------- %%%
%%% 	Utility functions	%%%
%%% --------------------------- %%%

%% Should be in string stdlib?

join_strings(Strings) ->
    lists:flatten(Strings).

-spec join_strings_with(Strings :: [string()], Separator :: string()) -> string().

join_strings_with([S1, S2 | R], S) ->
    join_strings_with([join_strings_with(S1,S2,S) | R], S);
join_strings_with([S], _) ->
    S.
join_strings_with(S1, S2, S) ->
    join_strings([S1,S,S2]).

%%% Generic erlang2html

-spec html_table(Rows :: [[string() | {'td' | 'th', string()}]]) -> string().

html_table(Rows) -> "<table>" ++ html_table_row(Rows) ++ "</table>".

html_table_row(Rows) -> html_table_row(Rows, odd).
html_table_row([], _) -> "";
html_table_row([Row|Rows], odd ) -> "<tr class=\"odd\">" ++ html_table_data(Row) ++ "</tr>" ++ html_table_row(Rows, even);
html_table_row([Row|Rows], even) -> "<tr class=\"even\">" ++ html_table_data(Row) ++ "</tr>" ++ html_table_row(Rows, odd ).

html_table_data([]) -> "";
html_table_data([{td, Data}|Row]) -> "<td>" ++ Data ++ "</td>" ++ html_table_data(Row);
html_table_data([{th, Data}|Row]) -> "<th>" ++ Data ++ "</th>" ++ html_table_data(Row);
html_table_data([Data|Row])       -> "<td>" ++ Data ++ "</td>" ++ html_table_data(Row).

-spec table_line(Table :: [any()]) -> string().

table_line(List) -> table_line(List, ["<tr>"]).
table_line([], Out) -> lists:flatten(lists:reverse(["</tr>\n"|Out]));
table_line([Element | Elements], Out) when is_list(Element) ->
    table_line(Elements, ["<td>" ++ Element ++ "</td>" |Out]);
table_line([Element | Elements], Out) ->
    table_line(Elements, ["<td>" ++ term2html(Element) ++ "</td>"|Out]).

-spec term2html(any()) -> string().

term2html(Term) when is_float(Term) -> lists:flatten(io_lib:format("~.4f", [Term]));
term2html(Term) -> lists:flatten(io_lib:format("~p", [Term])).

-spec mfa2html(MFA :: {atom(), atom(), list() | integer()}) -> string().

mfa2html({Module, Function, Arguments}) when is_list(Arguments) ->
    lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, length(Arguments)]));
mfa2html({Module, Function, Arity}) when is_integer(Arity) ->
    lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, Arity]));
mfa2html(_) ->
    "undefined".


-spec mfa2html_with_link({Pid::pid(),MFA :: {atom(), atom(), list() | integer()}}) -> string().

mfa2html_with_link({Pid, {Module, Function, Arguments}}) when is_list(Arguments) ->
    MFAString=lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, length(Arguments)])),
    MFAValue=lists:flatten(io_lib:format("{~p,~p,~p}", [Module, Function, length(Arguments)])),
    "<a href=\"/cgi-bin/percept_html/function_info_page?pid="++pid2value(Pid)++"&mfa="++MFAValue++"\">"++MFAString++"</a>";    
mfa2html_with_link({Pid, {Module, Function, Arity}}) when is_integer(Arity) ->
    MFAString=lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, Arity])),
    MFAValue=lists:flatten(io_lib:format("{~p,~p,~p}", [Module, Function, Arity])),
    "<a href=\"/cgi-bin/percept_html/function_info_page?pid="++pid2value(Pid)++"&mfa="++MFAValue++"\">"++MFAString++"</a>"; 
mfa2html_with_link(_) ->
    "undefined".

mfas2html_with_link(Pid, MFAs) ->
    lists:append(["{"++mfa2html_with_link({Pid,MFA})++", "++term2html(C)++"}"||{MFA, C}<-MFAs]).

-spec pid2html(Pid :: pid() | port()) -> string().

pid2html(Pid) when is_pid(Pid) ->
    PidString = term2html(Pid),
    PidValue = pid2value(Pid),
    "<a href=\"/cgi-bin/percept_html/process_info_page?pid="++PidValue++"\">"++PidString++"</a>";
pid2html(Pid) when is_port(Pid) ->
    term2html(Pid);
pid2html(_) ->
    "undefined".


pid2html_with_color(Pid) when is_pid(Pid) ->
    PidString = term2html(Pid),
    PidValue = pid2value(Pid),
    "<a href=\"/cgi-bin/percept_html/process_info_page?pid="++PidValue++"\">"
                  ++"<font color=\"#FF0000\">"++PidString++"</font></a>";
pid2html_with_color(Pid) when is_port(Pid) ->
    term2html(Pid);
pid2html_with_color(_) ->
    "undefined".

msg2html(Msg) ->
    AvgMsgSize = lists:last(tuple_to_list(Msg)),
    case AvgMsgSize < 1000 of   %% TODO: generalise this function!
        true ->
            term2html(Msg);
        false ->
            " <font color=\"#FF0000\">"++term2html(Msg)++"</font></a>"
    end.


-spec image_string(Request :: string()) -> string().

image_string(Request) ->
    "<img border=0 src=\"/cgi-bin/percept_graph/" ++
    Request ++ 
    " \">".

-spec image_string(atom() | string(), list()) -> string().

image_string(Request, Options) when is_atom(Request), is_list(Options) ->
     image_string(image_string_head(erlang:atom_to_list(Request), Options, []));
image_string(Request, Options) when is_list(Options) ->
     image_string(image_string_head(Request, Options, [])).

image_string_head(Request, [{Type, Value} | Opts], Out) when is_atom(Type), is_number(Value) ->
    Opt = join_strings(["?",term2html(Type),"=",term2html(Value)]),
    image_string_tail(Request, Opts, [Opt|Out]);
image_string_head(Request, [{Type, Value} | Opts], Out) ->
    Opt = join_strings(["?",Type,"=",Value]),
    image_string_tail(Request, Opts, [Opt|Out]).

image_string_tail(Request, [], Out) ->
    join_strings([Request | lists:reverse(Out)]);
image_string_tail(Request, [{Type, Value} | Opts], Out) when is_atom(Type), is_number(Value) ->
    Opt = join_strings(["&",term2html(Type),"=",term2html(Value)]),
    image_string_tail(Request, Opts, [Opt|Out]);
image_string_tail(Request, [{Type, Value} | Opts], Out) ->
    Opt = join_strings(["&",Type,"=",Value]),
    image_string_tail(Request, Opts, [Opt|Out]).
        
%%% percept conversions

-spec pid2value(Pid :: pid()) -> string().

pid2value(Pid) ->
    String = lists:flatten(io_lib:format("~p", [Pid])),
    lists:sublist(String, 2, erlang:length(String)-2).

-spec value2pid(Value :: string()) -> pid().

value2pid(Value) ->
   String = lists:flatten("<" ++ Value ++ ">"),
   erlang:list_to_pid(String).

string2mfa(String) ->
    Str=lists:sublist(String, 2, erlang:length(String)-2),
    [M, F, A] = string:tokens(Str, ","),
    F1=case hd(F) of 
           39 ->lists:sublist(F,2,erlang:length(F)-2);
           _ -> F
       end,
    {list_to_atom(M), list_to_atom(F1), list_to_integer(A)}.
    


%%% get value

-spec get_option_value(Option :: string(), Options :: [{string(),any()}]) ->
	{'error', any()} | boolean() | pid() | [pid()] | number().

get_option_value(Option, Options) ->
    case catch get_option_value0(Option, Options) of
	{'EXIT', Reason} -> {error, Reason};
	Value -> Value
    end.

get_option_value0(Option, Options) ->
     case lists:keysearch(Option, 1, Options) of
    	false -> get_default_option_value(Option);
	{value, {Option, _Value}} when Option == "fillcolor" -> true;
	{value, {Option, Value}} when Option == "pid" -> value2pid(Value);
	{value, {Option, Value}} when Option == "pids" -> 
	    [value2pid(PidValue) || PidValue <- string:tokens(Value,":")];
         {value, {Option, Value}} when Option =="mfa" ->
             string2mfa(Value);
         {value, {Option, Value}} -> get_number_value(Value);
         _ -> {error, undefined}
    end.

get_default_option_value(Option) ->
    case Option of 
    	"fillcolor" -> false;
	"range_min" -> float(0.0);
	"pids" -> [];
	"range_max" ->
	    Acts = percept_db:select({activity, []}),
	    #activity{ timestamp = Start } = hd(Acts),
	    #activity{ timestamp = Stop } = hd(lists:reverse(Acts)),
	    ?seconds(Stop,Start);
	"width" -> 800;
	"height" -> 400;
	_ -> {error, {undefined_default_option, Option}}
    end.

-spec get_number_value(string()) -> number() | {'error', 'illegal_number'}.

get_number_value(Value) ->
    % Try float
    case string:to_float(Value) of
    	{error, no_float} ->
	    % Try integer
	    case string:to_integer(Value) of
		{error, _} -> {error, illegal_number};
		{Integer, _} -> Integer
	    end;
	{error, _} -> {error, illegal_number};
	{Float, _} -> Float
    end.

%%% --------------------------- %%%
%%% 	html prime functions	%%%
%%% --------------------------- %%%

header() -> header([]).
header(HeaderData) ->
    "Content-Type: text/html\r\n\r\n" ++
    "<html>
    <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-1\">
    <title>percept</title>
    <link href=\"/css/percept.css\" rel=\"stylesheet\" type=\"text/css\">
    <script type=\"text/javascript\" src=\"/javascript/percept_error_handler.js\"></script>
    <script type=\"text/javascript\" src=\"/javascript/percept_select_all.js\"></script>
    <script type=\"text/javascript\" src=\"/javascript/percept_area_select.js\"></script>
    <script type=\"text/javascript\">
           function toggle(lnkid, tbid)
           {
           if(document.all)
		     {document.getElementById(tbid).style.display = document.getElementById(tbid).style.display == \"block\" ? \"none\" : \"block\";}
           else
		    {document.getElementById(tbid).style.display = document.getElementById(tbid).style.display == \"table\" ? \"none\" : \"table\";}
           document.getElementById(lnkid).value = document.getElementById(lnkid).value == \"[-]\" ? \"[+]\" : \"[-]\";
          }
           
    </script>
    " ++ HeaderData ++"
    </head>
    <body onLoad=\"load_image()\">
    <div id=\"header\"><a href=/index.html>percept</a></div>\n".

footer() ->
    "</body>
     </html>\n".

menu(Input) ->
    Query = httpd:parse_query(Input),
    Min = get_option_value("range_min", Query),
    Max = get_option_value("range_max", Query),
    "<div id=\"menu\" class=\"menu_tabs\">
	<ul>
     	<li><a href=/cgi-bin/percept_html/databases_page>databases</a></li>
        <li><a href=/cgi-bin/percept_html/functions_page?range_min=" ++
        term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">functions</a></li>
     	<li><a href=/cgi-bin/percept_html/processes_page?range_min=" ++
         term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">processes</a></li>
      	<li><a href=/cgi-bin/percept_html/page>overview</a></li>
     </ul></div>\n".

-spec error_msg(Error :: string()) -> string().

error_msg(Error) ->
    "<table width=300>
	<tr height=5><td></td> <td></td></tr>
	<tr><td width=150 align=right><b>Error: </b></td> <td align=left>"++ Error ++ "</td></tr>
	<tr height=5><td></td> <td></td></tr>
     </table>\n".


	%% <option disabled=true value=\""++ url_graph(Width, Height, Min, Max, []) ++"\" />Ports
	    	%% <option disabled=true value=\""++ url_graph(Width, Height, Min, Max, []) ++"\" />Processes
