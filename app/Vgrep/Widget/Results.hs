{-# LANGUAGE TemplateHaskell, DisambiguateRecordFields, MultiWayIf #-}
module Vgrep.Widget.Results where

import Control.Lens (Lens', over, set, view, _2, (&))
import Control.Lens.TH
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Sequence (Seq, ViewL(..), ViewR(..), (><), (|>), (<|))
import qualified Data.Sequence as Seq
import Data.Sequence.Lens
import Graphics.Vty (Image)
import Graphics.Vty.Prelude

import Vgrep.Widget.Type

data Buffer a = Buffer { _size :: !Int
                       , _pre  :: !(Seq a)
                       , _cur  :: !a
                       , _post :: !(Seq a) }

makeLenses ''Buffer


data ResultsState = State { _files     :: Buffer FileResults
                          , _scrollPos :: Int
                          , _region    :: DisplayRegion }

type FileResults = (String, Buffer Line)
type Line = (LineNumber, String)
type LineNumber = Int

makeLenses ''ResultsState


type ResultsWidget = Widget ResultsState

resultsWidget :: Map String [Line]
              -> DisplayRegion
              -> ResultsWidget
resultsWidget files dimensions =
    Widget { _state       = initState files dimensions
           , _dimensions  = dimensions
           , _resize      = undefined
           , _draw        = undefined
           , _handleEvent = undefined }

initBuffer :: [a] -> Buffer a
initBuffer as = Buffer { _size = length as
                       , _pre  = Seq.empty
                       , _cur  = head as -- FIXME partial function!
                       , _post = Seq.fromList (tail as) }

initState :: Map String [Line]
          -> DisplayRegion
          -> ResultsState
initState files dimensions =
    State { _files     = buffer
          , _scrollPos = 0
          , _region    = dimensions }
  where
    buffer = (initBuffer . map (over _2 initBuffer) . Map.toList) files


currentFile :: Lens' ResultsState (Buffer Line)
currentFile = files . cur . _2

previousLine :: ResultsState -> ResultsState
previousLine state = case view (currentFile . pre . viewR) state of
    EmptyR  -> previousFile state
    ls :> l -> state & set  (currentFile . pre) ls
                     & set  (currentFile . cur) l
                     & over (currentFile . post)
                            (view (currentFile . cur) state <|)
                     & updateScrollPos

previousFile :: ResultsState -> ResultsState
previousFile state = case view (files . pre . viewR) state of
    EmptyR  -> state
    fs :> f -> state & set  (files . pre) fs
                     & set  (files . cur) f
                     & over (files . post) (view (files . cur) state <|)
                     & updateScrollPos

nextLine :: ResultsState -> ResultsState
nextLine state = case view (currentFile . post . viewL) state of
    EmptyL  -> nextFile state
    l :< ls -> state & over (currentFile . pre)
                            (|> view (currentFile . cur) state)
                     & set  (currentFile . cur) l
                     & set  (currentFile . post) ls
                     & updateScrollPos

nextFile :: ResultsState -> ResultsState
nextFile state = case view (files . post . viewL) state of
    EmptyL  -> state
    f :< fs -> state & over (files . pre) (|> view (files . cur) state)
                     & set  (files . cur) f
                     & set  (files . post) fs
                     & updateScrollPos


updateScrollPos :: ResultsState -> ResultsState
updateScrollPos state =
    if | current < firstVisible -> state & set scrollPos current
       | current > lastVisible  -> state & set scrollPos (current - height + 1)
       | otherwise              -> state
  where
    height       = regionHeight (view region state)
    current      = computeCurrentItem (view files state)
    firstVisible = view scrollPos state
    lastVisible  = firstVisible + height - 1

computeCurrentItem :: Buffer FileResults -> Int
computeCurrentItem buffer = linesInFilesBeforeCurrent
                          + fileHeadersBeforeCurrent
                          + linesInCurrentFileBeforeCursor
  where
    fileHeadersBeforeCurrent = length (view pre buffer)
    linesInFilesBeforeCurrent =
        (sum . fmap length) (view (pre . traverse . _2 . pre) buffer)
    linesInCurrentFileBeforeCursor =
        (sum . fmap length) (view (cur . _2 . pre) buffer)
