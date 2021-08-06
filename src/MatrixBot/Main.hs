{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | The matrix-bot entrypoing
module MatrixBot.Main where

import qualified Data.Attoparsec.Text as P
import Dhall (auto, input)
import qualified Network.Matrix.Client as Matrix
import Relude
import UnliftIO.Exception (tryAny)

data Command
  = Hello
  | Hoogle Text
  | Eval Text
  deriving (Show)

onAction :: Matrix.ClientSession -> Matrix.RoomID -> Text -> Text -> Command -> IO ()
onAction session room sender eventId command = do
  let body =
        case command of
          Hello -> "Hello there " <> sender
          action -> "NotImplemented: " <> show action
      roomMessage =
        Matrix.RoomMessageText
          ( Matrix.MessageText
              { Matrix.mtBody = body,
                Matrix.mtFormat = Nothing,
                Matrix.mtFormattedBody = Nothing
              }
          )
      txnId = "reply-" <> eventId
  res <- Matrix.sendMessage session room (Matrix.EventRoomMessage roomMessage) (Matrix.TxnID txnId)
  case res of
    Left err -> error $ "Could not send message: " <> show err
    _ -> pure ()

commandParser :: P.Parser Command
commandParser = do
  P.skipWhile (`elem` [' ', '*'])
  _ <- P.char '>'
  P.skipWhile (== ' ')
  action <- P.takeWhile (/= ' ')
  P.skipWhile (== ' ')
  args <- P.takeText
  case action of
    ":hello" -> pure Hello
    ":hoogle" -> pure $ Hoogle args
    _ -> pure $ Eval $ action <> " " <> args

onMessage :: Matrix.ClientSession -> Matrix.RoomID -> Matrix.RoomEvent -> IO ()
onMessage session room event = case Matrix.reContent event of
  Matrix.EventRoomMessage (Matrix.RoomMessageText mt) ->
    case P.parseOnly (commandParser <* P.endOfInput) (Matrix.mtBody mt) of
      Right action -> onAction session room (Matrix.reSender event) (Matrix.reEventId event) action
      Left err -> putTextLn $ "Could not parse [" <> Matrix.mtBody mt <> "]: " <> show err
  _ -> pure ()

mainLoop :: Matrix.ClientSession -> Maybe Text -> IO ()
mainLoop session sinceM = do
  putTextLn $ "Requesting sync since: " <> show sinceM
  case sinceM of
    Just since -> writeFile ".cache" (toString since)
    _ -> pure ()
  srE <- Matrix.sync session Nothing sinceM (Just Matrix.Online) (Just 10_000)
  case srE of
    Left err -> error $ "Sync failed: " <> show err
    Right sr -> do
      let messages :: [(Matrix.RoomID, Matrix.RoomEvent)]
          messages = concatMap (\(room, events) -> fmap (room,) (toList events)) (Matrix.getTimelines sr)
      traverse_ (uncurry (onMessage session)) messages
      let since = Matrix.srNextBatch sr
      writeFile ".cache" (toString since)
      mainLoop session (Just since)

main :: IO ()
main = do
  putTextLn "MatrixBot starting..."
  config <- input auto "./config.dhall"
  session <- Matrix.createSession "https://matrix.org" =<< Matrix.getTokenFromEnv "MATRIX_TOKEN"
  since <- do
    sinceE <- tryAny $ readFile ".cache"
    pure $ case sinceE of
      Right since | since /= mempty -> pure (toText since)
      _ -> Nothing
  print =<< traverse (Matrix.joinRoom session) (config :: [Text])
  mainLoop session since
