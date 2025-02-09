module Ui exposing
    ( button
    , cardAttributes
    , columnCard
    , contentWidth
    , css
    , dangerButton
    , dateTimeInput
    , datestamp
    , datetimeToString
    , defaultFont
    , defaultFontColor
    , defaultFontSize
    , emailAddressText
    , enterKeyCode
    , error
    , externalLink
    , filler
    , formError
    , formLabelAbove
    , formLabelAboveEl
    , headerButton
    , headerLink
    , horizontalLine
    , inputBackground
    , inputBorder
    , inputBorderWidth
    , inputFocusClass
    , linkButton
    , linkColor
    , loadingError
    , loadingView
    , mailToLink
    , multiline
    , numberInput
    , onEnter
    , pageContentAttributes
    , radioGroup
    , routeLink
    , routeLinkNewTab
    , section
    , submitButton
    , submitColor
    , textInput
    , timeToString
    , title
    , titleFontSize
    )

import Colors exposing (..)
import Date exposing (Date)
import Element exposing (Element)
import Element.Background
import Element.Border
import Element.Font
import Element.Input
import Element.Region
import EmailAddress exposing (EmailAddress)
import Env
import Html exposing (Html)
import Html.Attributes
import Html.Events
import Id exposing (ButtonId(..), DateInputId(..), HtmlId, NumberInputId(..), RadioButtonId(..), TextInputId(..), TimeInputId(..))
import Json.Decode
import List.Nonempty exposing (Nonempty)
import Route exposing (Route)
import Svg
import Svg.Attributes
import Time
import Time.Extra as Time
import TimeExtra as Time


css : Html msg
css =
    Html.node "style"
        []
        [ Html.text """
          @import url('https://rsms.me/inter/inter.css');
          html { font-family: 'Inter', sans-serif; }
          @supports (font-variation-settings: normal) {
            html { font-family: 'Inter var', sans-serif; }
          }

          .linkFocus:focus {
              outline: solid #9bcbff !important;
          }

          .preserve-white-space {
              white-space: pre;
          }

          @keyframes fade-in {
            0% {opacity: 0;}
            50% {opacity: 0;}
            100% {opacity: 1;}
          }
        """
        ]


onEnter : msg -> Element.Attribute msg
onEnter msg =
    Html.Events.preventDefaultOn "keydown"
        (Json.Decode.field "keyCode" Json.Decode.int
            |> Json.Decode.andThen
                (\code ->
                    if code == enterKeyCode then
                        Json.Decode.succeed ( msg, True )

                    else
                        Json.Decode.fail "Not the enter key"
                )
        )
        |> Element.htmlAttribute


enterKeyCode =
    13


pageContentAttributes : List (Element.Attribute msg)
pageContentAttributes =
    [ Element.padding 8
    , Element.centerX
    , Element.width (Element.maximum 800 Element.fill)
    , Element.spacing 20
    ]


inputFocusClass : Element.Attribute msg
inputFocusClass =
    Element.htmlAttribute <| Html.Attributes.class "linkFocus"


horizontalLine : Element msg
horizontalLine =
    Element.el
        [ Element.width Element.fill
        , Element.height (Element.px 1)
        , Element.Background.color <| Element.rgb 0.2 0.2 0.2
        ]
        Element.none


headerButton : Bool -> HtmlId ButtonId -> { onPress : msg, label : String } -> Element msg
headerButton isMobile_ htmlId { onPress, label } =
    Element.Input.button
        [ Element.mouseOver [ Element.Background.color <| Element.rgba 1 1 1 0.5 ]
        , if isMobile_ then
            Element.padding 6

          else
            Element.padding 8
        , Element.Font.center
        , inputFocusClass
        , Id.htmlIdToString htmlId |> Html.Attributes.id |> Element.htmlAttribute
        , if isMobile_ then
            Element.Font.size 13

          else
            Element.Font.size 16
        ]
        { onPress = Just onPress
        , label = Element.text label
        }


headerLink : Bool -> Bool -> { route : Route, label : String } -> Element msg
headerLink isMobile_ isSelected { route, label } =
    Element.link
        [ Element.mouseOver [ Element.Background.color <| Element.rgba 1 1 1 0.5 ]
        , Element.below <|
            if isSelected then
                Element.el
                    [ Element.paddingXY 4 0, Element.width Element.fill ]
                    (Element.el
                        [ Element.Background.color Colors.green
                        , Element.width Element.fill
                        , Element.height (Element.px 2)
                        ]
                        Element.none
                    )

            else
                Element.none
        , if isMobile_ then
            Element.padding 6

          else
            Element.padding 8
        , Element.Font.center
        , if isMobile_ then
            Element.Font.size 13

          else
            Element.Font.size 16
        , inputFocusClass
        ]
        { url = Route.encode route
        , label = Element.text label
        }


emailAddressText : EmailAddress -> Element msg
emailAddressText emailAddress =
    Element.el
        [ Element.Font.bold ]
        (Element.text (EmailAddress.toString emailAddress))


routeLink : Route -> String -> Element msg
routeLink route label =
    Element.link
        [ Element.Font.color linkColor, inputFocusClass, Element.Font.underline ]
        { url = Route.encode route, label = Element.text label }


routeLinkNewTab : Route -> String -> Element msg
routeLinkNewTab route label =
    Element.newTabLink
        [ Element.Font.color linkColor, inputFocusClass, Element.Font.underline ]
        { url = "https://meetdown.app" ++ Route.encode route, label = Element.text label }


externalLink : String -> String -> Element msg
externalLink url label =
    Element.newTabLink
        [ Element.Font.color linkColor, inputFocusClass, Element.Font.underline ]
        { url = url, label = Element.text label }


mailToLink : String -> Maybe String -> Element msg
mailToLink emailAddress maybeSubject =
    Element.link
        [ Element.Font.color linkColor, inputFocusClass ]
        { url =
            "mailto:"
                ++ emailAddress
                ++ (case maybeSubject of
                        Just subject ->
                            "?subject=" ++ subject

                        Nothing ->
                            ""
                   )
        , label = Element.text emailAddress
        }


section : String -> Element msg -> Element msg
section sectionTitle content =
    Element.column
        [ Element.spacing 8
        , Element.Border.rounded 4
        , inputBackground False
        , Element.alignTop
        ]
        [ Element.paragraph [ Element.Font.bold ] [ Element.text sectionTitle ]
        , content
        ]


button : HtmlId ButtonId -> { onPress : msg, label : String } -> Element msg
button htmlId { onPress, label } =
    Element.Input.button
        [ Element.Border.width 2
        , Element.Border.color grey
        , Element.padding 8
        , Element.Border.rounded 4
        , Element.Font.center
        , Element.Font.color readingMuted
        , Element.width (Element.minimum 150 Element.fill)
        , Id.htmlIdToString htmlId |> Html.Attributes.id |> Element.htmlAttribute
        ]
        { onPress = Just onPress
        , label = Element.text label
        }


linkButton : { route : Route, label : String } -> Element msg
linkButton { route, label } =
    Element.link
        [ Element.Border.width 2
        , Element.Border.color grey
        , Element.padding 8
        , Element.Border.rounded 4
        , Element.Font.center
        , Element.Font.color readingMuted
        , Element.width (Element.minimum 150 Element.fill)
        ]
        { url = Route.encode route
        , label = Element.text label
        }


linkColor : Element.Color
linkColor =
    Colors.blue


submitColor : Element.Color
submitColor =
    Colors.green


submitButton : HtmlId ButtonId -> Bool -> { onPress : msg, label : String } -> Element msg
submitButton htmlId isSubmitting { onPress, label } =
    Element.Input.button
        [ Element.Background.color submitColor
        , Element.padding 10
        , Element.Border.rounded 4
        , Element.Font.center
        , Element.Font.color white
        , Id.htmlIdToString htmlId |> Html.Attributes.id |> Element.htmlAttribute
        , Element.width Element.fill
        ]
        { onPress = Just onPress
        , label =
            Element.el
                [ Element.width Element.fill
                , Element.paddingXY 30 0
                , if isSubmitting then
                    Element.inFront (Element.el [] (Element.text "⌛"))

                  else
                    Element.inFront Element.none
                ]
                (Element.text label)
        }


dangerButton : HtmlId ButtonId -> Bool -> { onPress : msg, label : String } -> Element msg
dangerButton htmlId isSubmitting { onPress, label } =
    Element.Input.button
        [ Element.Background.color Colors.red
        , Element.padding 10
        , Element.Border.rounded 4
        , Element.Font.center
        , Element.Font.color white
        , Id.htmlIdToString htmlId |> Html.Attributes.id |> Element.htmlAttribute
        ]
        { onPress = Just onPress
        , label =
            Element.el
                [ Element.width Element.fill
                , Element.paddingXY 30 0
                , if isSubmitting then
                    Element.inFront (Element.el [] (Element.text "⌛"))

                  else
                    Element.inFront Element.none
                ]
                (Element.text label)
        }


filler : Element.Length -> Element msg
filler length =
    Element.el [ Element.height length ] Element.none


titleFontSize : Element.Attr decorative msg
titleFontSize =
    Element.Font.size 28


defaultFont : Element.Attribute msg
defaultFont =
    Element.Font.family [ Element.Font.typeface "Inter" ]


defaultFontColor : Element.Attr decorative msg
defaultFontColor =
    Element.Font.color readingBlack


defaultFontSize : Element.Attr decorative msg
defaultFontSize =
    Element.Font.size 16


title : String -> Element msg
title text =
    Element.paragraph [ titleFontSize, Element.Region.heading 1 ] [ Element.text text ]


error : String -> Element msg
error errorMessage =
    Element.paragraph
        [ Element.paddingEach { left = 4, right = 4, top = 4, bottom = 0 }
        , Element.Font.color errorColor
        , Element.Font.size 14
        , Element.Font.medium
        ]
        [ Element.text errorMessage ]


errorColor : Element.Color
errorColor =
    Colors.red


formError : String -> Element msg
formError errorMessage =
    Element.paragraph
        [ Element.Font.color errorColor ]
        [ Element.text errorMessage ]


checkboxChecked =
    Svg.svg
        [ Svg.Attributes.width "60.768"
        , Svg.Attributes.height "60.768"
        , Svg.Attributes.viewBox "0 0 190 190"
        , Svg.Attributes.width "20px"
        , Svg.Attributes.height "20px"
        ]
        [ Svg.path
            [ Svg.Attributes.fill "current-color"
            , Svg.Attributes.stroke "#000"
            , Svg.Attributes.d "M34.22 112.47c3.31-3.31 12-11.78 16.37-15.78.91.78 18.79 18.07 19.03 18.31.38-.31 70.16-68.97 70.41-69.09.35.12 16.56 15.31 16.44 15.37-.17.25-86.73 86.78-86.8 86.9l-35.45-35.71zM25.91.06L69 .15h93C181.59.03 189.97 8.41 190 28v134c-.03 19.59-8.41 27.97-28 28H28c-19.59-.03-27.97-8.41-28-28V26C.17 12.01 7.61.09 25.91.06zM169 19H19v150h150V19z"
            ]
            []
        ]
        |> Element.html
        |> Element.el [ Element.alignTop ]


checkboxEmpty =
    Svg.svg
        [ Svg.Attributes.width "60.768"
        , Svg.Attributes.height "60.768"
        , Svg.Attributes.viewBox "0 0 190 190"
        , Svg.Attributes.width "20px"
        , Svg.Attributes.height "20px"
        ]
        [ Svg.path
            [ Svg.Attributes.fill "current-color"
            , Svg.Attributes.stroke "#000"
            , Svg.Attributes.d "M25.91.06L69 .15h93C181.59.03 189.97 8.41 190 28v134c-.03 19.59-8.41 27.97-28 28H28c-19.59-.03-27.97-8.41-28-28V26C.17 12.01 7.61.09 25.91.06zM169 19H19v150h150V19z"
            ]
            []
        ]
        |> Element.html
        |> Element.el [ Element.alignTop ]


radioGroup : (a -> HtmlId RadioButtonId) -> (a -> msg) -> Nonempty a -> Maybe a -> (a -> String) -> Maybe String -> Element msg
radioGroup htmlId onSelect options selected optionToLabel maybeError =
    let
        optionsView =
            List.Nonempty.map
                (\value ->
                    Element.Input.button
                        [ Element.width Element.fill
                        , Element.paddingXY 0 6
                        , htmlId value |> Id.htmlIdToString |> Html.Attributes.id |> Element.htmlAttribute
                        ]
                        { onPress = Just (onSelect value)
                        , label =
                            Element.row
                                []
                                [ if Just value == selected then
                                    checkboxChecked

                                  else
                                    checkboxEmpty
                                , optionToLabel value
                                    |> Element.text
                                    |> List.singleton
                                    |> Element.paragraph [ Element.paddingXY 8 0 ]
                                ]
                        }
                )
                options
                |> List.Nonempty.toList
    in
    optionsView
        ++ [ Maybe.map error maybeError |> Maybe.withDefault Element.none ]
        |> Element.column []


inputBackground : Bool -> Element.Attr decorative msg
inputBackground hasError =
    Element.Background.color <|
        if hasError then
            redLight

        else
            transparent


contentWidth : Element.Attribute msg
contentWidth =
    Element.width (Element.maximum 800 Element.fill)


inputBorder : Bool -> Element.Attr decorative msg
inputBorder hasError =
    Element.Border.color <|
        if hasError then
            red

        else
            darkGrey


inputBorderWidth : Bool -> Element.Attribute msg
inputBorderWidth hasError =
    Element.Border.width <|
        if hasError then
            2

        else
            1


textInput : HtmlId TextInputId -> (String -> msg) -> String -> String -> Maybe String -> Element msg
textInput htmlId onChange text labelText maybeError =
    Element.column
        [ Element.width Element.fill
        , Element.Border.rounded 4
        ]
        [ Element.Input.text
            [ Element.width Element.fill
            , Id.htmlIdToString htmlId |> Html.Attributes.id |> Element.htmlAttribute
            , inputBorder (maybeError /= Nothing)
            ]
            { text = text
            , onChange = onChange
            , placeholder = Nothing
            , label = formLabelAbove labelText
            }
        , Maybe.map error maybeError |> Maybe.withDefault Element.none
        ]


multiline : HtmlId TextInputId -> (String -> msg) -> String -> String -> Maybe String -> Element msg
multiline htmlId onChange text labelText maybeError =
    Element.column
        [ Element.width Element.fill
        , Element.Border.rounded 4
        ]
        [ Element.Input.multiline
            [ Element.width Element.fill
            , Element.height (Element.px 200)
            , Id.htmlIdToString htmlId |> Html.Attributes.id |> Element.htmlAttribute
            , inputBorder (maybeError /= Nothing)
            , inputBorderWidth (maybeError /= Nothing)
            ]
            { text = text
            , onChange = onChange
            , placeholder = Nothing
            , label = formLabelAbove labelText
            , spellcheck = True
            }
        , Maybe.map error maybeError |> Maybe.withDefault Element.none
        ]


numberInput : HtmlId NumberInputId -> (String -> msg) -> String -> String -> Maybe String -> Element msg
numberInput htmlId onChange value labelText maybeError =
    Element.column
        [ Element.spacing 4
        ]
        [ formLabelAboveEl labelText
        , Html.input
            ([ Html.Attributes.type_ "number"
             , Html.Events.onInput onChange
             , Id.htmlIdToString htmlId |> Html.Attributes.id
             , Html.Attributes.value value
             , Html.Attributes.style "line-height" "38px"
             , Html.Attributes.style "text-align" "right"
             , Html.Attributes.style "padding-right" "4px"
             ]
                ++ htmlInputBorderStyles
            )
            []
            |> Element.html
            |> Element.el []
        , maybeError |> Maybe.map error |> Maybe.withDefault Element.none
        ]


dateTimeInput :
    { dateInputId : HtmlId DateInputId
    , timeInputId : HtmlId TimeInputId
    , dateChanged : String -> msg
    , timeChanged : String -> msg
    , labelText : String
    , minTime : Time.Posix
    , timezone : Time.Zone
    , dateText : String
    , timeText : String
    , isDisabled : Bool
    , maybeError : Maybe String
    }
    -> Element msg
dateTimeInput { dateInputId, timeInputId, dateChanged, timeChanged, labelText, minTime, timezone, dateText, timeText, isDisabled, maybeError } =
    Element.column
        [ Element.spacing 4 ]
        [ formLabelAboveEl labelText
        , Element.wrappedRow [ Element.spacing 8 ]
            [ dateInput dateInputId dateChanged (Date.fromPosix timezone minTime) dateText isDisabled
            , timeInput timeInputId timeChanged timeText isDisabled
            ]
        , maybeError |> Maybe.map error |> Maybe.withDefault Element.none
        ]


timeInput : HtmlId TimeInputId -> (String -> msg) -> String -> Bool -> Element msg
timeInput htmlId onChange time isDisabled =
    Html.input
        ([ Html.Attributes.type_ "time"
         , Html.Events.onInput onChange
         , Html.Attributes.value time
         , Html.Attributes.style "padding" "5px"
         , Id.htmlIdToString htmlId |> Html.Attributes.id
         , Html.Attributes.disabled isDisabled
         ]
            ++ htmlInputBorderStyles
        )
        []
        |> Element.html
        |> Element.el []


timeToString : Time.Zone -> Time.Posix -> String
timeToString timezone time =
    String.fromInt (Time.toHour timezone time)
        ++ ":"
        ++ String.padLeft 2 '0' (String.fromInt (Time.toMinute timezone time))


dateInput : HtmlId DateInputId -> (String -> msg) -> Date -> String -> Bool -> Element msg
dateInput htmlId onChange minDateTime date isDisabled =
    Html.input
        ([ Html.Attributes.type_ "date"
         , Html.Attributes.min (datestamp minDateTime)
         , Html.Events.onInput onChange
         , Html.Attributes.value date
         , Html.Attributes.style "padding" "5px"
         , Id.htmlIdToString htmlId |> Html.Attributes.id
         , Html.Attributes.disabled isDisabled
         ]
            ++ htmlInputBorderStyles
        )
        []
        |> Element.html
        |> Element.el []


datetimeToString : Time.Zone -> Time.Posix -> String
datetimeToString timezone time =
    let
        offset =
            toFloat (Time.toOffset timezone time) / 60
    in
    (time |> Date.fromPosix timezone |> Date.format "MMMM ddd")
        ++ ", "
        ++ timeToString timezone time
        ++ (if offset >= 0 then
                Time.removeTrailing0s offset |> (++) " GMT+"

            else
                Time.removeTrailing0s offset |> (++) " GMT"
           )


datestamp : Date -> String
datestamp date =
    String.fromInt (Date.year date)
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt (Date.monthNumber date))
        ++ "-"
        ++ String.padLeft 2 '0' (String.fromInt (Date.day date))


formLabelAbove : String -> Element.Input.Label msg
formLabelAbove labelText =
    Element.Input.labelAbove
        [ Element.paddingEach { top = 0, right = 0, bottom = 5, left = 0 }
        , Element.Font.medium
        , Element.Font.size 13
        , Element.Font.color blueGrey
        ]
        (Element.paragraph [] [ Element.text labelText ])


formLabelAboveEl : String -> Element msg
formLabelAboveEl labelText =
    Element.el
        [ Element.paddingEach { top = 0, right = 0, bottom = 5, left = 0 }
        , Element.Font.medium
        , Element.Font.size 13
        , Element.Font.color blueGrey
        ]
        (Element.paragraph [] [ Element.text labelText ])


columnCard : List (Element msg) -> Element msg
columnCard children =
    Element.column
        (Element.width Element.fill
            :: Element.spacing 30
            :: cardAttributes
        )
        children


cardAttributes : List (Element.Attribute msg)
cardAttributes =
    [ Element.Border.rounded 4
    , Element.padding 15
    , Element.Border.width 1
    , Element.Border.color grey
    , Element.Border.shadow { offset = ( 0, 3 ), size = -1, blur = 3, color = grey }
    ]


loadingView : Element msg
loadingView =
    Element.el
        [ Element.Font.size 20
        , Element.centerX
        , Element.centerY
        , Element.htmlAttribute (Html.Attributes.style "animation-name" "fade-in")
        , Element.htmlAttribute (Html.Attributes.style "animation-duration" "1s")
        ]
        (Element.text "Loading")


loadingError : String -> Element msg
loadingError text =
    Element.el
        [ Element.Font.size 20
        , Element.centerX
        , Element.centerY
        , Element.Font.color errorColor
        ]
        (Element.text text)


htmlInputBorderStyles =
    [ Html.Attributes.style "border-color" (toCssString darkGrey)
    , Html.Attributes.style "border-width" "1px"
    , Html.Attributes.style "border-style" "solid"
    , Html.Attributes.style "border-radius" "4px"
    ]
