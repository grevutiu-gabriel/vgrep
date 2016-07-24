{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleContexts #-}
module Vgrep.Widget.EdLine (
      EdLineWidget
    , EdLine ()
    , edLine
    , edLineWidget
    , cursorPos
    , edLineText
    , reset
    , clear

    , putStatus
    , enterSearch
    , enterCmd
    
    , insert
    , delete
    , backspace
    ) where

import           Control.Lens              hiding (pre)
import           Control.Monad.State
import           Data.Text                 (Text)
import qualified Data.Text                 as Text
import           Data.Text.Zipper          (TextZipper)
import qualified Data.Text.Zipper          as Zipper
import           Graphics.Vty.Image
import           Graphics.Vty.Input.Events
import           Vgrep.Type
import           Vgrep.Widget.Type

type EdLineWidget = Widget EdLine

data EdLine = EdLine
    { _mode :: Mode
    , _zipper :: TextZipper Text }

data Mode = Cmd | Search | Status

makeLenses ''EdLine

cursorPos :: Getter EdLine Int
cursorPos = zipper . to Zipper.cursorPosition . _2

edLineText :: Getter EdLine Text
edLineText = zipper . to Zipper.getText . to head
-- We have to maintain the invariant that the TextZipper has exactly one line!

edLineWidget :: EdLineWidget
edLineWidget = Widget
    { initialize = edLine
    , draw       = drawWidget
    , cursor     = getCursor
    , handle     = handleEvent }

edLine :: EdLine
edLine = EdLine
    { _mode = Status
    , _zipper = emptyZipper }


emptyZipper :: TextZipper Text
emptyZipper = zipperOf Text.empty

zipperOf :: Text -> TextZipper Text
zipperOf txt = Zipper.mkZipper
    Text.singleton
    Text.drop
    Text.take
    Text.length
    Text.last
    Text.init
    Text.null
    [txt]
    (Just 1)

reset :: Monad m => VgrepT EdLine m Redraw
reset = put edLine >> pure Redraw

clear :: Monad m => VgrepT EdLine m Redraw
clear = assign zipper emptyZipper >> pure Redraw


putStatus :: Monad m => Text -> VgrepT EdLine m Redraw
putStatus txt = do
    put EdLine { _mode = Status, _zipper = zipperOf txt }
    pure Redraw

enterCmd :: Monad m => VgrepT EdLine m Redraw
enterCmd = do
    put EdLine { _mode = Cmd, _zipper = emptyZipper }
    pure Redraw

enterSearch :: Monad m => VgrepT EdLine m Redraw
enterSearch = do
    put EdLine { _mode = Search, _zipper = emptyZipper }
    pure Redraw


insert :: Monad m => Char -> VgrepT EdLine m Redraw
insert chr = modifying zipper (Zipper.insertChar chr) >> pure Redraw

delete :: Monad m => VgrepT EdLine m Redraw
delete = modifying zipper Zipper.deleteChar >> pure Redraw

backspace :: Monad m => VgrepT EdLine m Redraw
backspace = modifying zipper Zipper.deletePrevChar >> pure Redraw

moveLeft :: Monad m => VgrepT EdLine m Redraw
moveLeft = modifying zipper Zipper.moveLeft >> pure Redraw

moveRight :: Monad m => VgrepT EdLine m Redraw
moveRight = modifying zipper Zipper.moveRight >> pure Redraw

drawWidget :: Monad m => VgrepT EdLine m Image
drawWidget = use mode >>= \case
    Status -> use edLineText >>= render
    Cmd    -> use edLineText <&> Text.cons ':' >>= render
    Search -> use edLineText <&> Text.cons '/' >>= render
  where
    render txt = do
        (width, _) <- view region
        pure (text' defAttr (Text.justifyLeft width ' ' txt))

getCursor :: Monad m => VgrepT EdLine m Cursor
getCursor = use mode >>= \case
    Status -> pure NoCursor
    _otherwise -> uses cursorPos (\pos -> Cursor (pos + 1) 0)

handleEvent :: Monad m => Event -> EdLine -> Next (VgrepT EdLine m Redraw)
handleEvent event = view mode >>= \case
    Status -> pure Skip
    _otherwise -> pure . Continue $ case event of
        EvKey (KChar chr) [] -> insert chr
        EvKey KBS         [] -> backspace
        EvKey KDel        [] -> delete
        EvKey KLeft       [] -> moveLeft
        EvKey KRight      [] -> moveRight
        _otherwise           -> pure Unchanged
