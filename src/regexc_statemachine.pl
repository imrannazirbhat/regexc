:- module(regexc_statemachine,
  [
    ast_nfa/2,
    nfa_to_dot/2
  ]).

:- use_module(library(nb_set)).
:- use_module(regexc_utilities).

/** <module> regexc_statemachine

For the purposes of this module, a finite automaton is (Q, T, I, F) where:

  * Q: A finite set of states, {s_i}
  * T: A finite set of input transitions, {s_i X i -> s_j}
  * E: A finite set of epislon transitions, {s_i -> s_j}
  * I: An initial state
  * F: A set of accepting states

We assume that all finite Automotan here share the same set in input symbols, bytes.
For the purposes of specifying input in transitions we have two options.

  * range(Min, Max)
  * wildcard

Also note that a finite automaton is non-determinisitic unless E = [].

@author Sally Soul
@license MIT
*/

%
% This is a helper function for the top-level
%
initialize_partial_nfa(Partial_NFA) :-
  empty_nb_set(NFA_States),
  empty_nb_set(NFA_Transitions),
  empty_nb_set(NFA_Empty_Transitions),
  Partial_NFA = (NFA_States, NFA_Transitions, NFA_Empty_Transitions).

%! ast_nfa(+AST, -NFA) is det.
%
% This converts an AST into an NFA.
% Note that we use non-backtracking sets, so this is not bi-directional.
%
% @arg AST The AST the convert
% @arg NFA the resulting NFA
ast_nfa(AST, NFA) :-
  % We use non-backtracking sets to construct the NFA
  empty_nb_set(NFA_States),
  empty_nb_set(NFA_Transitions),
  empty_nb_set(NFA_Empty_Transitions),
  empty_nb_set(NFA_Final_States),

  % We only need the states and transitions for the construction though
  Partial_NFA = (NFA_States, NFA_Transitions, NFA_Empty_Transitions),

  % We use ast_nfa_r to recursivley build the NFA from the AST
  % Each recurrence returns produces an nfa (a sub nfa, if you will) that
  % is composed of a subset of the partial NFA. Each sub-NFA can
  % be refered to by a starting state, and an ending state

  Start_State = 0,
  add_nb_set(Start_State, NFA_States),
  Next_Available_State is Start_State + 1,

  % Start our recursive construction
  ast_nfa_r(
    AST,
    Partial_NFA,
    (Start_State, Final_State),
    (Next_Available_State, _)
  ),

  add_nb_set(Final_State, NFA_Final_States),

  NFA = (NFA_States, NFA_Transitions, NFA_Empty_Transitions, Start_State, NFA_Final_States).

% TODO: We do not support ast_not in the nfa process
% I Think we may need to seperate ast_not from range specific operations

%
% The following are ast_char_r definitions for each ast node type

%
% ast_range(Min, Max)
%
ast_nfa_r(
  ast_range(Min, Max),
  Partial_NFA,
  (Start_State, Final_State),
  (Final_State, Used_Until_State)
) :-
  (NFA_States, NFA_Transitions, _) = Partial_NFA,

  Used_Until_State is Final_State + 1,

  Transition_Input = range(Min, Max),
  add_nb_set(Final_State, NFA_States),
  add_nb_set((Start_State, Transition_Input, Final_State), NFA_Transitions ).

%
% ast_wildcard
%
ast_nfa_r(
  ast_wildcard,
  Partial_NFA,
  (Start_State, Final_State),
  (Final_State, Used_Until_State)
) :-
  (NFA_States, NFA_Transitions, _) = Partial_NFA,

  Used_Until_State is Final_State + 1,

  Transition_Input = wildcard,
  add_nb_set(Final_State, NFA_States),
  add_nb_set((Start_State, Transition_Input, Final_State), NFA_Transitions ).

%
% ast_concat(Left, Right)
%
ast_nfa_r(
  ast_concat(Sub_AST_L, Sub_AST_R),
  Partial_NFA,
  (Start_State, Final_State),
  (Next_Available_State, Used_Until_State)
) :-
  ast_nfa_r(
    Sub_AST_L,
    Partial_NFA,
    (Start_State, Sub_AST_R_Start),
    (Next_Available_State, L_Used_Until_State)
  ),

  ast_nfa_r(
    Sub_AST_R,
    Partial_NFA,
    (Sub_AST_R_Start, Final_State),
    (L_Used_Until_State, Used_Until_State)
  ).

%
% ast_or(Left, Right)
%
% We add a start state and a final state
% The left and right ASTS get convereted
% Then epsilon transitions are added from their starts
% to the new start state
% and from their final states to the new final state
ast_nfa_r(
  ast_or(Sub_AST_L, Sub_AST_R),
  Partial_NFA,
  (Start_State, Final_State),
  (Sub_AST_L_Start, Used_Until_State)
) :-
  (NFA_States, _, NFA_Empty_Transitions) = Partial_NFA,

  add_nb_set(Sub_AST_L_Start, NFA_States),
  Next_For_L is Sub_AST_L_Start + 1,

  ast_nfa_r(
    Sub_AST_L,
    Partial_NFA,
    (Sub_AST_L_Start, Sub_AST_L_Final),
    (Next_For_L, L_Used_Until_State)
  ),

  Sub_AST_R_Start = L_Used_Until_State,
  add_nb_set(Sub_AST_R_Start, NFA_States),

  Next_For_R is L_Used_Until_State + 1,

  ast_nfa_r(
    Sub_AST_R,
    Partial_NFA,
    (Sub_AST_R_Start, Sub_AST_R_Final),
    (Next_For_R, R_Used_Until_State)
  ),

  Final_State is R_Used_Until_State,
  Used_Until_State is Final_State + 1,
  add_nb_set(Final_State, NFA_States),

  add_nb_set((Start_State, Sub_AST_L_Start), NFA_Empty_Transitions),
  add_nb_set((Start_State, Sub_AST_R_Start), NFA_Empty_Transitions),
  add_nb_set((Sub_AST_L_Final, Final_State), NFA_Empty_Transitions),
  add_nb_set((Sub_AST_R_Final, Final_State), NFA_Empty_Transitions).


%
% ast_occurance(AST, Min, Max)
%
% We use two helper functions. First we
% make a machine for the Min occurances.
%
% Then we make a machine for (Max - Min) difference
ast_nfa_r(
  ast_occurance(Sub_AST, Min, Max),
  Partial_NFA,
  (Start_State, Final_State),
  (Next_Index, Used_Until_State)
) :-

  % Calculate the Min machine
  ast_nfa_min_r(
    (Sub_AST, Min),
    Partial_NFA,
    (Start_State, Min_Final),
    (Next_Index, Min_Used_Until)
  ),

  max_diff(Min, Max, Diff),

  ast_nfa_max(
    (Sub_AST, Diff),
    Partial_NFA,
    (Min_Final, Final_State),
    (Min_Used_Until, Used_Until_State)
  ).

%
% For a min bound of none or some(0), the machine is a no-op
%
ast_nfa_min_r(
  (_, Min),
  _,
  (Start_State, Start_State),
  (Next_State, Next_State)
  ) :-
    Min = none ; Min = some(0).

%
% For any defined Min bound above 0 we need to recursivley
% chain together the AST's machine
%
ast_nfa_min_r(
  (Sub_AST, some(N)),
  (Partial_NFA),
  (Start_State, Final_State),
  (Next_State, Used_Until_State)
) :-
  M is N - 1,

  ast_nfa_r(
    Sub_AST,
    Partial_NFA,
    (Start_State, Middle_State),
    (Next_State, Middle_Used_Until_State)
  ),

  ast_nfa_min_r(
    (Sub_AST, some(M)),
    Partial_NFA,
    (Middle_State, Final_State),
    (Middle_Used_Until_State, Used_Until_State)
  ).

%
% This is how we compute the difference between the Min and Max bounds
% The complexity is that if either bound is none, there is nother to do
%
max_diff(none, none, none).
max_diff(_, none, none).
max_diff(none, some(N), some(N)).
max_diff(some(Min), some(Max), some(Diff)) :- Diff is Max - Min.

%
% If the Max bound is none, then we take the AST's machine
% and add epsilon transitions from the start to the final state
% and vice-versa, so that it can be skipped or looped infinitley
%
ast_nfa_max(
  (Sub_AST, none),
  Partial_NFA,
  (Start_State, Final_State),
  (Next_State, Used_Until_State)
) :-

  (_, _, NFA_Empty_Transitions) = Partial_NFA,

  ast_nfa_r(
    Sub_AST,
    Partial_NFA,
    (Start_State, Final_State),
    (Next_State, Used_Until_State)
  ),

  add_nb_set((Start_State, Final_State), NFA_Empty_Transitions),
  add_nb_set((Final_State, Start_State), NFA_Empty_Transitions).

%
% For a finite Max bound, we recursiveley chain together the AST's machine
% However, each final state from the machine will have an epsilon transition
% to the real final state, so that the rest of the chain can be skipped
%
ast_nfa_max(
  (Sub_AST, some(N)),
  Partial_NFA,
  (Start_State, Final_State),
  (Next_State, Used_Until_State)
) :-
  (NFA_States, _, NFA_Empty_Transitions) = Partial_NFA,

  Final_State = Next_State,
  add_nb_set(Final_State, NFA_States),
  add_nb_set((Start_State, Final_State), NFA_Empty_Transitions),
  First_A_State is Final_State + 1,

  ast_nfa_max_r(
    (Sub_AST, N, Final_State),
    Partial_NFA,
    Start_State,
    (First_A_State, Used_Until_State)
  ).

%
% The recursive chaining for the Max bound
% Note that here we declare the Final state
%
ast_nfa_max_r(
  (_, 0, _),
  _Partial_NFA,
  _Start_State,
  (First_A_State, First_A_State)
).

ast_nfa_max_r(
  (Sub_AST, N, Final_State),
  Partial_NFA,
  Start_State,
  (Next_State, Used_Until_State)
) :-

  (_, _, NFA_Empty_Transitions) = Partial_NFA,

  ast_nfa_r(
    Sub_AST,
    Partial_NFA,
    (Start_State, Middle_State),
    (Next_State, Middle_Used_Until)
  ),

  add_nb_set((Middle_State, Final_State), NFA_Empty_Transitions),

  % Call recurrence with bound decreased by one
  M is N - 1,
  ast_nfa_max_r(
    (Sub_AST, M, Final_State),
    Partial_NFA,
    Middle_State,
    (Middle_Used_Until, Used_Until_State)
  ).


%
% The following are helper predicates
% To format each part of the NFA into its dot representation
%

state_to_dot(Stream, N) :-
  format(Stream, "\t~w;~n", N).

states_to_dot(Stream, NFA_States) :-
  nb_set_to_list(NFA_States, States),
  maplist(state_to_dot(Stream), States).

transition_to_dot(Stream, (Start_State, Input, Final_State)) :-
  format(Stream, "\t~w -> ~w [label=\"~w\"];~n", [Start_State, Final_State, Input]).

transitions_to_dot(Stream, NFA_Transitions) :-
  nb_set_to_list(NFA_Transitions, Transitions),
  maplist(transition_to_dot(Stream), Transitions).

empty_transition_to_dot(Stream, (Start_State, Final_State)) :-
  format(Stream, "\t~w -> ~w [label=\"ε\"];~n", [Start_State, Final_State]).

empty_transitions_to_dot(Stream, NFA_Transitions) :-
  nb_set_to_list(NFA_Transitions, Transitions),
  maplist(empty_transition_to_dot(Stream), Transitions).

final_state_to_dot(Stream, N) :-
  format(Stream, "\t~w [shape=doublecircle];~n", [N]).

final_states_to_dot(Stream, NFA_Final_States) :-
  nb_set_to_list(NFA_Final_States, Final_States),
  maplist(final_state_to_dot(Stream), Final_States).

start_state_to_dot(Stream, N) :-
  format(Stream, "\t~w [shape=box];~n", [N]).

%! nfa_to_dot(+NFA, +Stream) is det.
%
% Format the NFA into its dot representation
%
% @arg NFA The NFA to format
% @arg Output_Stream The stream to write the dot representation to
nfa_to_dot(NFA, Output_Stream) :-
  NFA = (NFA_States, NFA_Transitions, NFA_Empty_Transitions, Start_State, NFA_Final_States),
  writeln(Output_Stream, "digraph NFA {"),
  states_to_dot(Output_Stream, NFA_States),
  transitions_to_dot(Output_Stream, NFA_Transitions),
  empty_transitions_to_dot(Output_Stream, NFA_Empty_Transitions),
  final_states_to_dot(Output_Stream, NFA_Final_States),
  start_state_to_dot(Output_Stream, Start_State),
  writeln(Output_Stream, "}").

:- begin_tests(regexc_statemachine).

test_dot_output(String, Correct_Dot_File) :-
  regex_ast:string_ast(String, AST, Errors),
  assertion(Errors = []),
	ast_nfa(AST, Nfa),

  tmp_file_stream(text, Test_File, TO), close(TO),
  write_to_file_once(nfa_to_dot(Nfa), Test_File, Deterministic),
  assertion(Deterministic = true),
  file_diff(Test_File, Correct_Dot_File, Diff),

  string_length(Diff, Diff_Length),
  assertion(Diff_Length = 0),
  (Diff = "" ; format("~n~w~n", [Diff])).

test(ast_to_string) :-
  Dot_Files = [
    (
      "a",
      "tests/nfa/nfa_1.dot"
    ),
    (
      "a|b|c",
      "tests/nfa/nfa_2.dot"
    ),
    (
      "(a|b|c){2,3}abc+",
      "tests/nfa/nfa_3.dot"
    ),
    (
      "a*b+c?(.|(ca)){3,7}",
      "tests/nfa/nfa_4.dot"
    )
  ],
  forall(member((String, Correct_Dot_File), Dot_Files),
    assertion(test_dot_output(String, Correct_Dot_File))
  ).

:- end_tests(regexc_statemachine).
