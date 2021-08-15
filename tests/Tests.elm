module Tests exposing
    ( createEventAndAnotherUserNotLoggedInButWithAnExistingAccountJoinsIt
    , createEventAndAnotherUserNotLoggedInJoinsIt
    , suite
    )

import AssocList as Dict
import BackendEffect exposing (HttpBody(..))
import BackendLogic
import CreateGroupPage
import Date
import Dict as RegularDict
import Duration
import EmailAddress exposing (EmailAddress)
import Env
import FrontendLogic
import Group exposing (EventId)
import GroupName exposing (GroupName)
import GroupPage
import Html.Parser
import Http
import Id exposing (ClientId, GroupId, Id)
import Json.Decode
import List.Extra as List
import LoginForm
import Postmark
import ProfilePage
import Quantity
import Route exposing (Route)
import Test exposing (..)
import Test.Html.Query
import Test.Html.Selector
import TestFramework as TF
import Time
import Types exposing (BackendModel, BackendMsg, FrontendModel(..), FrontendMsg(..), LoadedFrontend, LoginStatus(..), ToBackend(..), ToFrontend)
import Ui
import Unsafe
import Untrusted
import Url


frontendApp =
    { init = FrontendLogic.init
    , update = FrontendLogic.update
    , onUrlRequest = UrlClicked
    , onUrlChange = UrlChanged
    , updateFromBackend = FrontendLogic.updateFromBackend
    , subscriptions = FrontendLogic.subscriptions
    , view = FrontendLogic.view
    }


testApp : TF.TestApp ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
testApp =
    TF.testApp
        frontendApp
        { init = BackendLogic.init
        , update = BackendLogic.update
        , updateFromFrontend = BackendLogic.updateFromFrontend
        , subscriptions = BackendLogic.subscriptions
        }
        handleHttpRequests


handleHttpRequests : { currentRequest : TF.HttpRequest, httpRequests : List TF.HttpRequest } -> Http.Response String
handleHttpRequests { currentRequest, httpRequests } =
    Http.GoodStatus_
        { url = currentRequest.url
        , statusCode = 200
        , statusText = "OK"
        , headers = RegularDict.empty
        }
        ""


checkLoadedFrontend :
    ClientId
    -> (LoadedFrontend -> Result String ())
    -> TF.Instructions ToBackend FrontendMsg FrontendModel toFrontend backendMsg backendModel
    -> TF.Instructions ToBackend FrontendMsg FrontendModel toFrontend backendMsg backendModel
checkLoadedFrontend clientId checkFunc state =
    TF.checkFrontend
        clientId
        (\frontend ->
            case frontend of
                Loaded loaded ->
                    checkFunc loaded

                Loading _ ->
                    Err "Frontend is still loading"
        )
        state


loginFromHomepage :
    Bool
    -> Id.SessionId
    -> Id.SessionId
    -> EmailAddress.EmailAddress
    ->
        ({ instructions : TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel, clientId : Id.ClientId, clientIdFromEmail : Id.ClientId }
         -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
        )
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
loginFromHomepage loginWithEnterKey sessionId sessionIdFromEmail emailAddress stateFunc =
    testApp.connectFrontend sessionId
        (Unsafe.url Env.domain)
        (\( state3, clientId ) ->
            state3
                |> testApp.simulateTime Duration.second
                |> testApp.clickButton clientId FrontendLogic.signUpOrLoginButtonId
                |> handleLoginForm loginWithEnterKey clientId sessionIdFromEmail emailAddress stateFunc
        )


handleLoginForm :
    Bool
    -> Id.ClientId
    -> Id.SessionId
    -> EmailAddress
    ->
        ({ instructions : TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel, clientId : Id.ClientId, clientIdFromEmail : Id.ClientId }
         -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
        )
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
handleLoginForm loginWithEnterKey clientId sessionIdFromEmail emailAddress andThenFunc state =
    state
        |> testApp.simulateTime Duration.second
        |> testApp.inputText clientId LoginForm.emailAddressInputId (EmailAddress.toString emailAddress)
        |> testApp.simulateTime Duration.second
        |> (if loginWithEnterKey then
                TF.keyDownEvent frontendApp clientId LoginForm.emailAddressInputId Ui.enterKeyCode

            else
                testApp.clickButton clientId LoginForm.submitButtonId
           )
        |> testApp.simulateTime Duration.second
        |> TF.andThen
            (\state3 ->
                case List.filterMap isLoginEmail state3.httpRequests |> List.head of
                    Just loginEmail ->
                        if loginEmail.emailAddress == emailAddress then
                            TF.continueWith state3
                                |> testApp.connectFrontend
                                    sessionIdFromEmail
                                    (Unsafe.url (BackendLogic.loginEmailLink loginEmail.route loginEmail.loginToken loginEmail.maybeJoinEvent))
                                    (\( state4, clientIdFromEmail ) ->
                                        andThenFunc
                                            { instructions = state4 |> testApp.simulateTime Duration.second
                                            , clientId = clientId
                                            , clientIdFromEmail = clientIdFromEmail
                                            }
                                    )

                        else
                            TF.continueWith state3 |> TF.checkState (\_ -> Err "Got a login email but it was to the wrong address")

                    _ ->
                        TF.continueWith state3 |> TF.checkState (\_ -> Err "Should have gotten a login email")
            )


decodePostmark : Json.Decode.Decoder ( String, EmailAddress, List Html.Parser.Node )
decodePostmark =
    Json.Decode.map3 (\subject to body -> ( subject, to, body ))
        (Json.Decode.field "Subject" Json.Decode.string)
        (Json.Decode.field "To" Json.Decode.string
            |> Json.Decode.andThen
                (\to ->
                    case EmailAddress.fromString to of
                        Just emailAddress ->
                            Json.Decode.succeed emailAddress

                        Nothing ->
                            Json.Decode.fail "Invalid email address"
                )
        )
        (Json.Decode.field "HtmlBody" Json.Decode.string
            |> Json.Decode.andThen
                (\html ->
                    case Html.Parser.run html of
                        Ok nodes ->
                            Json.Decode.succeed nodes

                        Err _ ->
                            Json.Decode.fail "Failed to parse html"
                )
        )


isLoginEmail :
    TF.HttpRequest
    ->
        Maybe
            { emailAddress : EmailAddress
            , route : Route
            , loginToken : Id Id.LoginToken
            , maybeJoinEvent : Maybe ( Id GroupId, EventId )
            }
isLoginEmail httpRequest =
    if String.startsWith (Postmark.endpoint ++ "/email") httpRequest.url then
        case httpRequest.body of
            JsonBody value ->
                case Json.Decode.decodeValue decodePostmark value of
                    Ok ( subject, to, body ) ->
                        case ( subject, getRoutesFromHtml body ) of
                            ( "Meetdown login link", [ ( route, Route.LoginToken loginToken maybeJoinEvent ) ] ) ->
                                { emailAddress = to
                                , route = route
                                , loginToken = loginToken
                                , maybeJoinEvent = maybeJoinEvent
                                }
                                    |> Just

                            _ ->
                                Nothing

                    Err _ ->
                        Nothing

            _ ->
                Nothing

    else
        Nothing


isReminderEmail :
    TF.HttpRequest
    -> Maybe { emailAddress : EmailAddress, groupId : Id GroupId, groupName : GroupName }
isReminderEmail httpRequest =
    if String.startsWith (Postmark.endpoint ++ "/email") httpRequest.url then
        case httpRequest.body of
            JsonBody value ->
                case Json.Decode.decodeValue decodePostmark value of
                    Ok ( _, to, body ) ->
                        case getRoutesFromHtml body of
                            [ ( Route.GroupRoute groupId groupName, Route.NoToken ) ] ->
                                { emailAddress = to
                                , groupId = groupId
                                , groupName = groupName
                                }
                                    |> Just

                            _ ->
                                Nothing

                    Err _ ->
                        Nothing

            _ ->
                Nothing

    else
        Nothing


gotReminder : EmailAddress -> List TF.HttpRequest -> Bool
gotReminder emailAddress httpRequests =
    List.filterMap isReminderEmail httpRequests
        |> List.any (\reminder -> reminder.emailAddress == emailAddress)


isDeleteUserEmail :
    TF.HttpRequest
    ->
        Maybe
            { emailAddress : EmailAddress
            , route : Route
            , deleteUserToken : Id Id.DeleteUserToken
            }
isDeleteUserEmail httpRequest =
    if String.startsWith (Postmark.endpoint ++ "/email") httpRequest.url then
        case httpRequest.body of
            JsonBody value ->
                case Json.Decode.decodeValue decodePostmark value of
                    Ok ( subject, to, body ) ->
                        case ( subject, getRoutesFromHtml body ) of
                            ( "Confirm account deletion", [ ( route, Route.DeleteUserToken deleteUserToken ) ] ) ->
                                { emailAddress = to
                                , route = route
                                , deleteUserToken = deleteUserToken
                                }
                                    |> Just

                            _ ->
                                Nothing

                    Err _ ->
                        Nothing

            _ ->
                Nothing

    else
        Nothing


getRoutesFromHtml : List Html.Parser.Node -> List ( Route, Route.Token )
getRoutesFromHtml nodes =
    List.filterMap
        (\( attributes, _ ) ->
            let
                maybeHref =
                    List.filterMap
                        (\( name, value ) ->
                            if name == "href" then
                                Just value

                            else
                                Nothing
                        )
                        attributes
                        |> List.head
            in
            maybeHref |> Maybe.andThen Url.fromString |> Maybe.andThen Route.decode
        )
        (findNodesByTag "a" nodes)


findNodesByTag : String -> List Html.Parser.Node -> List ( List Html.Parser.Attribute, List Html.Parser.Node )
findNodesByTag tagName nodes =
    List.concatMap
        (\node ->
            case node of
                Html.Parser.Element name attributes children ->
                    (if name == tagName then
                        [ ( attributes, children ) ]

                     else
                        []
                    )
                        ++ findNodesByTag tagName children

                _ ->
                    []
        )
        nodes


suite : Test
suite =
    describe "App tests"
        [ test "Login from homepage and submit with login button" <|
            \_ ->
                let
                    sessionId =
                        Id.sessionIdFromString "session0"

                    emailAddress =
                        Unsafe.emailAddress "the@email.com"
                in
                testApp.init
                    |> loginFromHomepage False
                        sessionId
                        sessionId
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            instructions
                                |> checkLoadedFrontend
                                    clientIdFromEmail
                                    (\frontend ->
                                        case frontend.loginStatus of
                                            LoggedIn loggedIn ->
                                                if loggedIn.emailAddress == emailAddress then
                                                    Ok ()

                                                else
                                                    "Incorrect email address "
                                                        ++ EmailAddress.toString loggedIn.emailAddress
                                                        |> Err

                                            _ ->
                                                Err "Failed to log in"
                                    )
                        )
                    |> TF.toExpectation
        , test "Login from homepage and submit with enter key" <|
            \_ ->
                let
                    sessionId =
                        Id.sessionIdFromString "session0"

                    emailAddress =
                        Unsafe.emailAddress "the@email.com"
                in
                testApp.init
                    |> loginFromHomepage
                        True
                        sessionId
                        sessionId
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            instructions
                                |> checkLoadedFrontend
                                    clientIdFromEmail
                                    (\frontend ->
                                        case frontend.loginStatus of
                                            LoggedIn loggedIn ->
                                                if loggedIn.emailAddress == emailAddress then
                                                    Ok ()

                                                else
                                                    "Incorrect email address "
                                                        ++ EmailAddress.toString loggedIn.emailAddress
                                                        |> Err

                                            _ ->
                                                Err "Failed to log in"
                                    )
                        )
                    |> TF.toExpectation
        , test "Login from homepage and check that original clientId also got logged in since it's on the same session" <|
            \_ ->
                let
                    sessionId =
                        Id.sessionIdFromString "session0"

                    emailAddress =
                        Unsafe.emailAddress "the@email.com"
                in
                testApp.init
                    |> loginFromHomepage
                        True
                        sessionId
                        sessionId
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            instructions
                                |> checkLoadedFrontend
                                    clientId
                                    (\frontend ->
                                        case frontend.loginStatus of
                                            LoggedIn loggedIn ->
                                                if loggedIn.emailAddress == emailAddress then
                                                    Ok ()

                                                else
                                                    "Incorrect email address "
                                                        ++ EmailAddress.toString loggedIn.emailAddress
                                                        |> Err

                                            _ ->
                                                Err "Failed to log in"
                                    )
                        )
                    |> TF.toExpectation
        , test "Login from homepage and check that original clientId did not get logged since it has a different sessionId" <|
            \_ ->
                testApp.init
                    |> loginFromHomepage
                        True
                        (Id.sessionIdFromString "session0")
                        (Id.sessionIdFromString "session1")
                        (Unsafe.emailAddress "the@email.com")
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            instructions
                                |> checkLoadedFrontend
                                    clientId
                                    (\frontend ->
                                        case frontend.loginStatus of
                                            LoggedIn _ ->
                                                Err "Should not have been logged in"

                                            NotLoggedIn _ ->
                                                Ok ()

                                            LoginStatusPending ->
                                                Err "Failed to check login"
                                    )
                        )
                    |> TF.toExpectation
        , test "Login from homepage and check it's not possible to use the same login token twice" <|
            \_ ->
                let
                    emailAddress =
                        Unsafe.emailAddress "the@email.com"

                    sessionId =
                        Id.sessionIdFromString "session0"
                in
                testApp.init
                    |> loginFromHomepage True
                        sessionId
                        sessionId
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            instructions
                                |> TF.andThen
                                    (\state ->
                                        case List.filterMap isLoginEmail state.httpRequests of
                                            [ loginEmail ] ->
                                                TF.continueWith state
                                                    |> testApp.connectFrontend
                                                        (Id.sessionIdFromString "session1")
                                                        (Unsafe.url
                                                            (BackendLogic.loginEmailLink
                                                                loginEmail.route
                                                                loginEmail.loginToken
                                                                loginEmail.maybeJoinEvent
                                                            )
                                                        )
                                                        (\( state2, clientId3 ) ->
                                                            state2
                                                                |> testApp.simulateTime Duration.second
                                                                |> checkLoadedFrontend
                                                                    clientId3
                                                                    (\frontend ->
                                                                        case frontend.loginStatus of
                                                                            LoggedIn _ ->
                                                                                Err "Should not have been logged in"

                                                                            NotLoggedIn _ ->
                                                                                if frontend.hasLoginTokenError then
                                                                                    Ok ()

                                                                                else
                                                                                    Err "Correctly didn't log in but failed to show error"

                                                                            LoginStatusPending ->
                                                                                Err "Failed to check login"
                                                                    )
                                                        )

                                            _ ->
                                                Debug.todo "Didn't find login email"
                                    )
                        )
                    |> TF.toExpectation
        , test "Creating a group redirects to newly created group page" <|
            \_ ->
                let
                    session0 =
                        Id.sessionIdFromString "session0"

                    groupName =
                        "It's my Group!"

                    groupDescription =
                        "This is the best group"
                in
                testApp.init
                    |> loginFromHomepage False
                        session0
                        session0
                        (Unsafe.emailAddress "the@email.com")
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            createGroup clientIdFromEmail groupName groupDescription instructions
                                |> TF.checkFrontend clientIdFromEmail
                                    (\model ->
                                        case model of
                                            Loaded loaded ->
                                                case Dict.keys loaded.cachedGroups of
                                                    [ groupId ] ->
                                                        if loaded.route == Route.GroupRoute groupId (Unsafe.groupName groupName) then
                                                            Ok ()

                                                        else
                                                            Err "Was redirected to incorrect route"

                                                    _ ->
                                                        Err "No cached groups were found"

                                            Loading _ ->
                                                Err "Somehow we ended up in the loading state"
                                    )
                                |> testApp.checkView
                                    clientIdFromEmail
                                    (Test.Html.Query.has
                                        [ Test.Html.Selector.text groupName
                                        , Test.Html.Selector.text groupDescription
                                        ]
                                    )
                        )
                    |> TF.toExpectation
        , test "Create an event and get an email a day before it occurs" <|
            \_ ->
                let
                    session0 =
                        Id.sessionIdFromString "session0"

                    emailAddress =
                        Unsafe.emailAddress "the@email.com"
                in
                testApp.init
                    |> loginFromHomepage False
                        session0
                        session0
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            createGroupAndEvent
                                clientId
                                { groupName = "It's my Group!"
                                , groupDescription = "This is the best group"
                                , eventName = "First group event!"
                                , eventDescription = "We're gonna party!"
                                , eventDate = Date.fromPosix Time.utc (Duration.addTo TF.startTime (Duration.days 3))
                                , eventHour = 14
                                , eventMinute = 0
                                , eventDuration = "1"
                                }
                                instructions
                                |> TF.fastForward (Duration.days 1.999 |> Quantity.plus (Duration.hours 14))
                                |> TF.checkState
                                    (\model ->
                                        if gotReminder emailAddress model.httpRequests then
                                            Err "Shouldn't have gotten an event notification yet"

                                        else
                                            Ok ()
                                    )
                                |> testApp.simulateTime (Duration.days 0.002)
                                |> TF.checkState
                                    (\model ->
                                        if gotReminder emailAddress model.httpRequests then
                                            Ok ()

                                        else
                                            Err "Should have gotten an event notification"
                                    )
                        )
                    |> TF.toExpectation
        , test "Create an event and but don't get a notification if it's occurring within 24 hours" <|
            \_ ->
                let
                    session0 =
                        Id.sessionIdFromString "session0"

                    emailAddress =
                        Unsafe.emailAddress "the@email.com"
                in
                testApp.init
                    |> loginFromHomepage False
                        session0
                        session0
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            createGroupAndEvent
                                clientId
                                { groupName = "It's my Group!"
                                , groupDescription = "This is the best group"
                                , eventName = "First group event!"
                                , eventDescription = "We're gonna party!"
                                , eventDate = Date.fromPosix Time.utc TF.startTime
                                , eventHour = 14
                                , eventMinute = 0
                                , eventDuration = "1"
                                }
                                instructions
                                |> TF.fastForward (Duration.hours 1.99)
                                |> testApp.simulateTime (Duration.hours 0.02)
                                |> TF.checkState
                                    (\model ->
                                        if gotReminder emailAddress model.httpRequests then
                                            Err "Shouldn't have gotten an event notification"

                                        else
                                            Ok ()
                                    )
                        )
                    |> TF.toExpectation
        , test "Create an event and another user joins it and gets an event reminder" <|
            \_ ->
                let
                    session0 =
                        Id.sessionIdFromString "session0"

                    session1 =
                        Id.sessionIdFromString "session1"

                    emailAddress0 =
                        Unsafe.emailAddress "the@email.com"

                    emailAddress1 =
                        Unsafe.emailAddress "jim@a.com"

                    groupName =
                        Unsafe.groupName "It's my Group!"
                in
                testApp.init
                    |> loginFromHomepage False
                        session0
                        session0
                        emailAddress0
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            createGroupAndEvent
                                clientId
                                { groupName = GroupName.toString groupName
                                , groupDescription = "This is the best group"
                                , eventName = "First group event!"
                                , eventDescription = "We're gonna party!"
                                , eventDate = Date.fromPosix Time.utc (Duration.addTo TF.startTime Duration.day)
                                , eventHour = 14
                                , eventMinute = 0
                                , eventDuration = "1"
                                }
                                instructions
                        )
                    |> loginFromHomepage False
                        session1
                        session1
                        emailAddress1
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            findSingleGroup
                                (\groupId inProgress2 ->
                                    inProgress2
                                        |> testApp.inputText clientId FrontendLogic.groupSearchId "my group!"
                                        |> TF.keyDownEvent frontendApp clientId FrontendLogic.groupSearchId Ui.enterKeyCode
                                        |> testApp.simulateTime Duration.second
                                        |> testApp.clickLink clientId (Route.GroupRoute groupId groupName)
                                        |> testApp.simulateTime Duration.second
                                        |> testApp.clickButton clientId GroupPage.joinEventButtonId
                                        |> testApp.simulateTime Duration.second
                                        |> TF.fastForward (Duration.hours 14)
                                        |> testApp.simulateTime (Duration.seconds 30)
                                        |> TF.checkState
                                            (\model ->
                                                if gotReminder emailAddress1 model.httpRequests then
                                                    Ok ()

                                                else
                                                    Err "Should have gotten an event notification"
                                            )
                                )
                                instructions
                        )
                    |> TF.toExpectation
        , test "Create an event and another user (who isn't logged in) joins it" <|
            \_ -> TF.toExpectation createEventAndAnotherUserNotLoggedInJoinsIt
        , test "Create an event and another user (who isn't logged in but has an account) joins it" <|
            \_ -> TF.toExpectation createEventAndAnotherUserNotLoggedInButWithAnExistingAccountJoinsIt
        , test "Rate limit login for a given email address" <|
            \_ ->
                let
                    connectAndLogin count =
                        testApp.connectFrontend
                            (Id.sessionIdFromString <| "session " ++ String.fromInt count)
                            (Unsafe.url Env.domain)
                            (\( state, clientId ) ->
                                state
                                    |> testApp.simulateTime Duration.second
                                    |> testApp.clickButton clientId FrontendLogic.signUpOrLoginButtonId
                                    |> testApp.inputText clientId LoginForm.emailAddressInputId "my+good@email.eu"
                                    |> testApp.clickButton clientId LoginForm.submitButtonId
                                    |> testApp.simulateTime Duration.second
                            )
                in
                testApp.init
                    |> connectAndLogin 1
                    |> connectAndLogin 2
                    |> connectAndLogin 3
                    |> connectAndLogin 4
                    |> TF.checkState
                        (\state2 ->
                            if List.filterMap isLoginEmail state2.httpRequests |> List.length |> (==) 1 then
                                Ok ()

                            else
                                Err "Only one email should have been sent"
                        )
                    |> testApp.simulateTime (Duration.minutes 2)
                    |> connectAndLogin 5
                    |> TF.checkState
                        (\state2 ->
                            if List.filterMap isLoginEmail state2.httpRequests |> List.length |> (==) 2 then
                                Ok ()

                            else
                                Err "Two emails should have been sent"
                        )
                    |> TF.toExpectation
        , test "Rate limit login for a given session" <|
            \_ ->
                let
                    session0 =
                        Id.sessionIdFromString "session0"
                in
                testApp.init
                    |> testApp.connectFrontend
                        session0
                        (Unsafe.url Env.domain)
                        (\( state, clientId ) ->
                            state
                                |> testApp.simulateTime Duration.second
                                |> testApp.clickButton clientId FrontendLogic.signUpOrLoginButtonId
                                |> testApp.inputText clientId LoginForm.emailAddressInputId "a@email.eu"
                                |> testApp.clickButton clientId LoginForm.submitButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.inputText clientId LoginForm.emailAddressInputId "b@email.eu"
                                |> testApp.clickButton clientId LoginForm.submitButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.inputText clientId LoginForm.emailAddressInputId "c@email.eu"
                                |> testApp.clickButton clientId LoginForm.submitButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.inputText clientId LoginForm.emailAddressInputId "d@email.eu"
                                |> testApp.clickButton clientId LoginForm.submitButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.inputText clientId LoginForm.emailAddressInputId "e@email.eu"
                                |> testApp.clickButton clientId LoginForm.submitButtonId
                                |> testApp.simulateTime Duration.second
                                |> TF.checkState
                                    (\state2 ->
                                        let
                                            count =
                                                List.filterMap isLoginEmail state2.httpRequests |> List.length
                                        in
                                        if count == 1 then
                                            Ok ()

                                        else
                                            "Only one email should have been sent, got "
                                                ++ String.fromInt count
                                                ++ " instead"
                                                |> Err
                                    )
                                |> testApp.simulateTime Duration.minute
                                |> testApp.inputText clientId LoginForm.emailAddressInputId "e@email.eu"
                                |> testApp.clickButton clientId LoginForm.submitButtonId
                                |> testApp.simulateTime Duration.second
                                |> TF.checkState
                                    (\state2 ->
                                        let
                                            count =
                                                List.filterMap isLoginEmail state2.httpRequests |> List.length
                                        in
                                        if count == 2 then
                                            Ok ()

                                        else
                                            "Two emails should have been sent, got "
                                                ++ String.fromInt count
                                                ++ " instead"
                                                |> Err
                                    )
                        )
                    |> TF.toExpectation
        , test "Rate limit delete account email" <|
            \_ ->
                let
                    session0 =
                        Id.sessionIdFromString "session0"

                    emailAddress =
                        Unsafe.emailAddress "a@email.eu"
                in
                testApp.init
                    |> loginFromHomepage
                        True
                        session0
                        session0
                        emailAddress
                        (\{ instructions, clientId, clientIdFromEmail } ->
                            instructions
                                |> testApp.simulateTime Duration.second
                                |> testApp.clickLink clientId Route.MyProfileRoute
                                |> testApp.clickButton clientId ProfilePage.deleteAccountButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.clickButton clientId ProfilePage.deleteAccountButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.clickButton clientId ProfilePage.deleteAccountButtonId
                                |> testApp.simulateTime Duration.second
                                |> testApp.clickButton clientId ProfilePage.deleteAccountButtonId
                                |> testApp.simulateTime Duration.second
                                |> TF.checkState
                                    (\state2 ->
                                        let
                                            count =
                                                List.count
                                                    (\httpRequest ->
                                                        case isDeleteUserEmail httpRequest of
                                                            Just deleteUserEmail ->
                                                                deleteUserEmail.emailAddress == emailAddress

                                                            Nothing ->
                                                                False
                                                    )
                                                    state2.httpRequests
                                        in
                                        if count == 1 then
                                            Ok ()

                                        else
                                            "Only one account deletion email should have been sent, got "
                                                ++ String.fromInt count
                                                ++ " instead"
                                                |> Err
                                    )
                                |> testApp.simulateTime (Duration.minutes 1.5)
                                |> testApp.clickButton clientId ProfilePage.deleteAccountButtonId
                                |> testApp.simulateTime Duration.second
                                |> TF.checkState
                                    (\state2 ->
                                        let
                                            count =
                                                List.count
                                                    (\httpRequest ->
                                                        case isDeleteUserEmail httpRequest of
                                                            Just deleteUserEmail ->
                                                                deleteUserEmail.emailAddress == emailAddress

                                                            Nothing ->
                                                                False
                                                    )
                                                    state2.httpRequests
                                        in
                                        if count == 2 then
                                            Ok ()

                                        else
                                            "Two account deletion emails should have been sent, got "
                                                ++ String.fromInt count
                                                ++ " instead"
                                                |> Err
                                    )
                        )
                    |> TF.toExpectation
        , test "Not logged in users can't create groups" <|
            \_ ->
                let
                    sessionId =
                        Id.sessionIdFromString "sessionId"
                in
                testApp.init
                    |> testApp.connectFrontend
                        sessionId
                        (Env.domain ++ Route.encode Route.HomepageRoute |> Unsafe.url)
                        (\( instructions, clientId ) ->
                            instructions
                                |> TF.sendToBackend
                                    sessionId
                                    clientId
                                    (CreateGroupRequest
                                        (Unsafe.groupName "group" |> Untrusted.untrust)
                                        (Unsafe.description "description" |> Untrusted.untrust)
                                        Group.PublicGroup
                                    )
                        )
                    |> testApp.simulateTime Duration.second
                    |> TF.checkBackend
                        (\backend ->
                            if Dict.isEmpty backend.groups then
                                Ok ()

                            else
                                Err "No group should have been created"
                        )
                    |> TF.toExpectation
        , test "Non-admin users can't delete groups" <|
            \_ ->
                let
                    sessionId =
                        Id.sessionIdFromString "sessionId"

                    attackerSessionId =
                        Id.sessionIdFromString "sessionIdAttacker"

                    emailAddress =
                        Unsafe.emailAddress "my@email.com"

                    attackerEmailAddress =
                        Unsafe.emailAddress "hacker@email.com"
                in
                testApp.init
                    |> loginFromHomepage
                        True
                        sessionId
                        sessionId
                        emailAddress
                        (\{ instructions, clientId } ->
                            instructions |> createGroup clientId "group" "description"
                        )
                    |> testApp.simulateTime Duration.second
                    |> loginFromHomepage
                        False
                        attackerSessionId
                        attackerSessionId
                        attackerEmailAddress
                        (\{ instructions, clientId } ->
                            findSingleGroup
                                (\groupId instructions2 ->
                                    instructions2
                                        |> TF.sendToBackend
                                            sessionId
                                            clientId
                                            (GroupRequest groupId GroupPage.DeleteGroupAdminRequest)
                                )
                                instructions
                        )
                    |> testApp.simulateTime Duration.second
                    |> TF.checkBackend
                        (\backend ->
                            if Dict.isEmpty backend.deletedGroups && Dict.size backend.groups == 1 then
                                Ok ()

                            else
                                Err "No group should have been deleted"
                        )
                    |> TF.toExpectation
        ]


findSingleGroup :
    (Id GroupId
     -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
     -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
    )
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
findSingleGroup continueWith inProgress =
    inProgress
        |> TF.andThen
            (\state ->
                case Dict.keys state.backend.groups of
                    [ groupId ] ->
                        TF.continueWith state
                            |> continueWith groupId

                    keys ->
                        TF.continueWith state
                            |> TF.checkState
                                (\_ ->
                                    "Expected to find exactly one group, instead got "
                                        ++ String.fromInt (List.length keys)
                                        |> Err
                                )
            )


createEventAndAnotherUserNotLoggedInJoinsIt : TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
createEventAndAnotherUserNotLoggedInJoinsIt =
    let
        session0 =
            Id.sessionIdFromString "session0"

        session1 =
            Id.sessionIdFromString "session1"

        emailAddress0 =
            Unsafe.emailAddress "the@email.se"

        emailAddress1 =
            Unsafe.emailAddress "jim@a.com"

        groupName =
            Unsafe.groupName "It's my Group!"
    in
    testApp.init
        |> loginFromHomepage False
            session0
            session0
            emailAddress0
            (\{ instructions, clientId, clientIdFromEmail } ->
                createGroupAndEvent
                    clientId
                    { groupName = GroupName.toString groupName
                    , groupDescription = "This is the best group"
                    , eventName = "First group event!"
                    , eventDescription = "We're gonna party!"
                    , eventDate = Date.fromPosix Time.utc (Duration.addTo TF.startTime Duration.day)
                    , eventHour = 14
                    , eventMinute = 0
                    , eventDuration = "1"
                    }
                    instructions
            )
        |> testApp.connectFrontend session1
            (Env.domain ++ Route.encode Route.HomepageRoute |> Unsafe.url)
            (\( instructions, clientId ) ->
                findSingleGroup
                    (\groupId inProgress2 ->
                        inProgress2
                            |> testApp.simulateTime Duration.second
                            |> testApp.inputText clientId FrontendLogic.groupSearchId "my group!"
                            |> TF.keyDownEvent frontendApp clientId FrontendLogic.groupSearchId Ui.enterKeyCode
                            |> testApp.simulateTime Duration.second
                            |> testApp.clickLink clientId (Route.GroupRoute groupId groupName)
                            |> testApp.simulateTime Duration.second
                            |> testApp.clickButton clientId GroupPage.joinEventButtonId
                            |> testApp.simulateTime Duration.second
                            |> handleLoginForm
                                True
                                clientId
                                session1
                                emailAddress1
                                (\a ->
                                    a.instructions
                                        |> testApp.simulateTime Duration.second
                                        -- We are just clicking the leave button to test that we had joined the event.
                                        |> testApp.clickButton a.clientIdFromEmail GroupPage.leaveEventButtonId
                                )
                    )
                    instructions
            )


createEventAndAnotherUserNotLoggedInButWithAnExistingAccountJoinsIt : TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
createEventAndAnotherUserNotLoggedInButWithAnExistingAccountJoinsIt =
    let
        session0 =
            Id.sessionIdFromString "session0"

        session1 =
            Id.sessionIdFromString "session1"

        emailAddress0 =
            Unsafe.emailAddress "the@email.com"

        emailAddress1 =
            Unsafe.emailAddress "jim@a.com"

        groupName =
            Unsafe.groupName "It's my Group!"
    in
    testApp.init
        |> loginFromHomepage False
            session0
            session0
            emailAddress0
            (\{ instructions, clientId, clientIdFromEmail } ->
                createGroupAndEvent
                    clientId
                    { groupName = GroupName.toString groupName
                    , groupDescription = "This is the best group"
                    , eventName = "First group event!"
                    , eventDescription = "We're gonna party!"
                    , eventDate = Date.fromPosix Time.utc (Duration.addTo TF.startTime Duration.day)
                    , eventHour = 14
                    , eventMinute = 0
                    , eventDuration = "1"
                    }
                    instructions
            )
        |> loginFromHomepage False
            session1
            session1
            emailAddress1
            (\{ instructions, clientIdFromEmail } ->
                instructions
                    |> testApp.simulateTime Duration.second
                    |> testApp.clickButton clientIdFromEmail FrontendLogic.logOutButtonId
                    |> testApp.simulateTime Duration.minute
            )
        |> testApp.connectFrontend session1
            (Env.domain ++ Route.encode Route.HomepageRoute |> Unsafe.url)
            (\( instructions, clientId ) ->
                findSingleGroup
                    (\groupId inProgress2 ->
                        inProgress2
                            |> testApp.simulateTime Duration.second
                            |> testApp.inputText clientId FrontendLogic.groupSearchId "my group!"
                            |> TF.keyDownEvent frontendApp clientId FrontendLogic.groupSearchId Ui.enterKeyCode
                            |> testApp.simulateTime Duration.second
                            |> testApp.clickLink clientId (Route.GroupRoute groupId groupName)
                            |> testApp.simulateTime Duration.second
                            |> testApp.clickButton clientId GroupPage.joinEventButtonId
                            |> testApp.simulateTime Duration.second
                            |> handleLoginForm
                                True
                                clientId
                                session1
                                emailAddress1
                                (\a ->
                                    a.instructions
                                        |> testApp.simulateTime Duration.second
                                        -- We are just clicking the leave button to test that we had joined the event.
                                        |> testApp.clickButton a.clientIdFromEmail GroupPage.leaveEventButtonId
                                )
                    )
                    instructions
            )


createGroup :
    Id.ClientId
    -> String
    -> String
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
createGroup loggedInClient groupName groupDescription state =
    state
        |> testApp.clickLink loggedInClient Route.CreateGroupRoute
        |> testApp.simulateTime Duration.second
        |> testApp.inputText loggedInClient CreateGroupPage.nameInputId groupName
        |> testApp.inputText loggedInClient CreateGroupPage.descriptionInputId groupDescription
        |> testApp.clickRadioButton loggedInClient (CreateGroupPage.groupVisibilityId Group.PublicGroup)
        |> testApp.clickButton loggedInClient CreateGroupPage.submitButtonId
        |> testApp.simulateTime Duration.second


createGroupAndEvent :
    Id.ClientId
    ->
        { groupName : String
        , groupDescription : String
        , eventName : String
        , eventDescription : String
        , eventDate : Date.Date
        , eventHour : Int
        , eventMinute : Int
        , eventDuration : String
        }
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
    -> TF.Instructions ToBackend FrontendMsg FrontendModel ToFrontend BackendMsg BackendModel
createGroupAndEvent loggedInClient { groupName, groupDescription, eventName, eventDescription, eventDate, eventHour, eventMinute, eventDuration } state =
    createGroup loggedInClient groupName groupDescription state
        |> testApp.clickButton loggedInClient GroupPage.createNewEventId
        |> testApp.inputText loggedInClient GroupPage.eventNameInputId eventName
        |> testApp.inputText loggedInClient GroupPage.eventDescriptionInputId eventDescription
        |> testApp.clickRadioButton loggedInClient (GroupPage.eventMeetingTypeId GroupPage.MeetOnline)
        |> testApp.inputDate loggedInClient GroupPage.createEventStartDateId eventDate
        |> testApp.inputTime loggedInClient GroupPage.createEventStartTimeId eventHour eventMinute
        |> testApp.inputNumber loggedInClient GroupPage.eventDurationId eventDuration
        |> testApp.clickButton loggedInClient GroupPage.createEventSubmitId
        |> testApp.simulateTime Duration.second
