:- module(statemachine,
  [
    ast_nfa/2
  ]).

:- use_module(library(nb_set)).

/** <module> statemachine

For the purposes of this module, a finite automaton is (Q, T, I, F) where:

Q: A finite set of states, {s_i}
T: A finite set of input transitions, {s_i X i -> s_j}
E: A finite set of epislon transitions, {s_i -> s_j}
I: An initial state
F: A set of accepting states

We assume that all finite Automotan here share the same set in input symbols, bytes.
For the purposes of specifying input in transitions we have three options.

byte(Byte),
range(Min, Max),
any.

Also note that a finite automaton is non-determinisitic unless E = []. 

@author Sally Soul
@license MIT
*/

ast_nfa(Root_Node, NFA) :-
  % We use non-backtracking sets to construct the NFA
  empty_nb_set(NFA_States),
  empty_nb_set(NFA_Transitions),
  empty_nb_set(NFA_Empty_Transitions),
  empty_nb_set(NFA_Final_States),

  % We only need the states and transitions for the construction though
  Partial_NFA = (NFA_States, NFA_Transitions, NFA_Empty_Transitions),

  % We use ast_nfa_r to recursivley build the NFA from the AST
  % Each recurrence refers to a nfa that is composed of a subset of the
  % partial NFA. Each sub-NFA can be refered to by a starting state,
  % and an ending state
  Sub_NFA = (Start_State, Final_State),

  % Start our recursive construction
  ast_nfa_r(Root_Node, Partial_NFA, 0, _, Sub_NFA),

  % Create the final states set, and we have our finished NFA
  add_nb_set(Final_State, NFA_Final_States),
  NFA = (NFA_States, NFA_Transitions, NFA_Empty_Transitions, Start_State, NFA_Final_States).

%
% ast_char(X)
% state(N) -- X --> state(N+1)
%
ast_nfa_r(
  ast_char(X),
  Partial_NFA,
  Current_Index,
  Next_Index,
  (State_Start, State_Final)
) :-
  Partial_NFA = (NFA_States, NFA_Transitions, _),

  State_Start = state(Current_Index),
  Next_Index_1 is Current_Index + 1,
  State_Final = state(Next_Index_1),

  add_nb_set(State_Start, NFA_States),
  add_nb_set(State_Final, NFA_States),
  add_nb_set((State_Start, X, State_Final), NFA_Transitions ),

  Next_Index is Current_Index + 1.
/*
ast_nfa_r(
	ast_occurance(N, Min, Max),
	Partial_NFA,
	Current_Index,
	Next_Index,
	(State_Start, State_Final),
) :-
	Partial_NFA = (NFA_States, NFA_Transitions, _),
*/