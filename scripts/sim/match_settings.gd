class_name MatchSettings
extends RefCounted

## The rules of a match, in one place.

## Captures that win the match straight away.
var capture_limit := 5
## Match length in seconds. The team with most captures wins when it runs out.
var time_limit := 1200.0
## Seconds a dropped flag lies before it goes home by itself.
var flag_return_time := 30.0
## How close a soldier's body has to be to touch a flag or a stand, in metres.
var flag_touch_range := 1.6
var stand_touch_range := 2.2
