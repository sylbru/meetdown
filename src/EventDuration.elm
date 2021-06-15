module EventDuration exposing (Error(..), EventDuration, errorToString, fromMinutes, maxLength, removeTrailing0s, toDuration, toMinutes, toString)

import Duration exposing (Duration)


type EventDuration
    = EventDuration Int


type Error
    = EventDurationNotGreaterThan0
    | EventDurationTooLong


errorToString : Error -> String
errorToString error =
    case error of
        EventDurationNotGreaterThan0 ->
            "Value must be greater than 0"

        EventDurationTooLong ->
            "The event can't be more than " ++ String.fromInt (maxLength // 60) ++ " hours long"


maxLength : number
maxLength =
    60 * 24 * 7


fromMinutes : Int -> Result Error EventDuration
fromMinutes minutes =
    if minutes <= 0 then
        Err EventDurationNotGreaterThan0

    else if minutes > maxLength then
        Err EventDurationTooLong

    else
        Ok (EventDuration minutes)


toMinutes : EventDuration -> Int
toMinutes (EventDuration minutes) =
    minutes


toDuration : EventDuration -> Duration
toDuration (EventDuration minutes) =
    Duration.minutes (toFloat minutes)


toString : EventDuration -> String
toString eventDuration =
    let
        minutes =
            toMinutes eventDuration

        hours =
            toFloat minutes / 60
    in
    if minutes >= 60 then
        removeTrailing0s hours
            |> String.left 4
            |> (\a ->
                    if a == "1" then
                        "1 hour"

                    else
                        a ++ " hours"
               )

    else if minutes == 1 then
        "1 minute"

    else
        String.fromInt minutes ++ " minutes"


removeTrailing0s : Float -> String
removeTrailing0s =
    String.fromFloat
        >> String.foldr
            (\char newText ->
                if newText == "" && (char == '0' || char == '.') then
                    newText

                else
                    newText ++ String.fromChar char
            )
            ""
