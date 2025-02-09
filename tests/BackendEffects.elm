module BackendEffects exposing (BackendEffect(..), effects)

import BackendLogic exposing (Effects)
import EmailAddress exposing (EmailAddress)
import Event exposing (Event)
import Group exposing (EventId)
import GroupName exposing (GroupName)
import Http
import Id exposing (ClientId, DeleteUserToken, GroupId, Id, LoginToken)
import Postmark
import Route exposing (Route)
import SendGrid
import Time
import Types exposing (BackendMsg, ToFrontend)


type BackendEffect
    = Batch (List BackendEffect)
    | None
    | SendToFrontend ClientId ToFrontend
    | SendLoginEmail (Result Http.Error Postmark.PostmarkSendResponse -> BackendMsg) EmailAddress Route (Id LoginToken) (Maybe ( Id GroupId, EventId ))
    | SendDeleteUserEmail (Result Http.Error Postmark.PostmarkSendResponse -> BackendMsg) EmailAddress (Id DeleteUserToken)
    | SendEventReminderEmail (Result Http.Error Postmark.PostmarkSendResponse -> BackendMsg) (Id GroupId) GroupName Event Time.Zone EmailAddress
    | GetTime (Time.Posix -> BackendMsg)


effects : Effects BackendEffect
effects =
    { batch = Batch
    , none = None
    , sendToFrontend = SendToFrontend
    , sendToFrontends =
        \clientIds toFrontend ->
            List.map (\clientId -> SendToFrontend clientId toFrontend) clientIds |> Batch
    , sendLoginEmail = SendLoginEmail
    , sendDeleteUserEmail = SendDeleteUserEmail
    , sendEventReminderEmail = SendEventReminderEmail
    , getTime = GetTime
    }
