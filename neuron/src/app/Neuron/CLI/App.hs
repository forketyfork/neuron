{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.CLI.App
  ( run,
  )
where

import Control.Concurrent.Async (race_)
import Data.Tagged
import Data.Time
  ( getCurrentTime,
    getCurrentTimeZone,
    utcToLocalTime,
  )
import qualified Neuron.Backend as Backend
import qualified Neuron.CLI.Logging as Logging
import Neuron.CLI.New (newZettelFile)
import Neuron.CLI.Open (openLocallyGeneratedFile)
import Neuron.CLI.Parser (commandParser)
import Neuron.CLI.Query (runQuery)
import Neuron.CLI.Search (interactiveSearch)
import Neuron.CLI.Types
import qualified Neuron.LSP as LSP
import qualified Neuron.Version as Version
import Options.Applicative
import Relude
import System.Console.ANSI (hSupportsANSI)
import System.Directory (getCurrentDirectory)

run :: (Bool -> App ()) -> IO ()
run act = do
  defaultNotesDir <- getCurrentDirectory
  cliParser <- commandParser defaultNotesDir <$> now
  app <-
    execParser $
      info
        (versionOption <*> cliParser <**> helper)
        (fullDesc <> progDesc "Neuron, future-proof Zettelkasten app <https://neuron.zettel.page/>")
  useColors <- hSupportsANSI stdout
  let logAction = Logging.mkLogAction useColors
  runApp (Env app logAction) $ runAppCommand act
  where
    versionOption =
      infoOption
        (toString $ untag Version.neuronVersion)
        (long "version" <> help "Show version")
    now = do
      tz <- getCurrentTimeZone
      utcToLocalTime tz <$> liftIO getCurrentTime

runAppCommand :: (Bool -> App ()) -> App ()
runAppCommand genAct = do
  getCommand >>= \case
    LSP -> do
      LSP.lspServer
    Gen GenCommand {..} -> do
      case serve of
        Just (host, port) -> do
          outDir <- getOutputDir
          appEnv <- getAppEnv
          liftIO $
            race_ (runApp appEnv $ genAct watch) $ do
              runApp appEnv $ Backend.serve host port outDir
        Nothing ->
          genAct watch
    New newCommand ->
      newZettelFile newCommand
    Open openCommand ->
      openLocallyGeneratedFile openCommand
    Query queryCommand -> do
      runQuery queryCommand
    Search searchCmd -> do
      interactiveSearch searchCmd
