{-# LANGUAGE BangPatterns, OverloadedStrings #-}
module QC.ByteString (tests) where

import Control.Applicative ((<$>), (<*>))
import Data.Char (chr, ord)
import Data.Int (Int64)
import Data.Word (Word8)
import Prelude hiding (take, takeWhile)
import QC.Common (liftOp, parseBS, toStrictBS)
import Test.Framework (Test)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck
import qualified Data.Attoparsec.ByteString as P
import qualified Data.Attoparsec.ByteString.Char8 as P8
import qualified Data.Attoparsec.ByteString.FastSet as S
import qualified Data.Attoparsec.ByteString.Lazy as PL
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import qualified Data.ByteString.Lazy.Char8 as L8

-- Basic byte-level combinators.

satisfy :: Word8 -> L.ByteString -> Property
satisfy w s = parseBS (P.satisfy (<=w)) (L.cons w s) === Just w

satisfyWith :: Char -> L.ByteString -> Property
satisfyWith c s = parseBS (P.satisfyWith (chr . fromIntegral) (<=c))
                         (L.cons (fromIntegral (ord c)) s) === Just c

word8 :: Word8 -> L.ByteString -> Property
word8 w s = parseBS (P.word8 w) (L.cons w s) === Just w

skip :: Word8 -> L.ByteString -> Property
skip w s =
  case (parseBS (P.skip (<w)) s, L.uncons s) of
    (Nothing, mcs) -> maybe (property True) (expectFailure . it) mcs
    (Just _,  mcs) -> maybe (property False) it mcs
  where it cs = liftOp "<" (<) (fst cs) w

anyWord8 :: L.ByteString -> Property
anyWord8 s
    | L.null s  = p === Nothing
    | otherwise = p === Just (L.head s)
  where p = parseBS P.anyWord8 s

notWord8 :: Word8 -> NonEmptyList Word8 -> Property
notWord8 w (NonEmpty s) = parseBS (P.notWord8 w) bs === if v == w
                                                        then Nothing
                                                        else Just v
    where v = L.head bs
          bs = L.pack s

peekWord8 :: L.ByteString -> Property
peekWord8 s
    | L.null s  = p === Just (Nothing, s)
    | otherwise = p === Just (Just (L.head s), s)
  where p = parseBS ((,) <$> P.peekWord8 <*> P.takeLazyByteString) s

peekWord8' :: L.ByteString -> Property
peekWord8' s = parseBS P.peekWord8' s === (fst <$> L.uncons s)

string :: L.ByteString -> L.ByteString -> Property
string s t = parseBS (P.string s') (s `L.append` t) === Just s'
  where s' = toStrictBS s

skipWhile :: Word8 -> L.ByteString -> Property
skipWhile w s =
    let t = L.dropWhile (<=w) s
    in case PL.parse (P.skipWhile (<=w)) s of
         PL.Done t' () -> t === t'
         _             -> property False

takeCount :: Positive Int -> L.ByteString -> Property
takeCount (Positive k) s =
    case parseBS (P.take k) s of
      Nothing -> liftOp ">" (>) (fromIntegral k) (L.length s)
      Just _s -> liftOp "<=" (<=) (fromIntegral k) (L.length s)

takeWhile :: Word8 -> L.ByteString -> Property
takeWhile w s =
    let (h,t) = L.span (==w) s
    in case PL.parse (P.takeWhile (==w)) s of
         PL.Done t' h' -> t === t' .&&. toStrictBS h === h'
         _             -> property False

take :: Int -> L.ByteString -> Property
take n s = maybe (property $ L.length s < fromIntegral n)
           (=== B.take n (toStrictBS s)) $
           parseBS (P.take n) s

takeByteString :: L.ByteString -> Property
takeByteString s = maybe (property False) (=== toStrictBS s) .
                   parseBS P.takeByteString $ s

takeLazyByteString :: L.ByteString -> Property
takeLazyByteString s = maybe (property False) (=== s) .
                       parseBS P.takeLazyByteString $ s

takeWhile1 :: Word8 -> L.ByteString -> Property
takeWhile1 w s =
    let s'    = L.cons w s
        (h,t) = L.span (<=w) s'
    in case PL.parse (P.takeWhile1 (<=w)) s' of
         PL.Done t' h' -> t === t' .&&. toStrictBS h === h'
         _             -> property False

takeTill :: Word8 -> L.ByteString -> Property
takeTill w s =
    let (h,t) = L.break (==w) s
    in case PL.parse (P.takeTill (==w)) s of
         PL.Done t' h' -> t === t' .&&. toStrictBS h === h'
         _             -> property False

takeWhile1_empty :: Property
takeWhile1_empty = parseBS (P.takeWhile1 undefined) L.empty === Nothing

endOfInput :: L.ByteString -> Property
endOfInput s = parseBS P.endOfInput s === if L.null s
                                          then Just ()
                                          else Nothing

endOfLine :: L.ByteString -> Property
endOfLine s =
  case (parseBS P8.endOfLine s, L8.uncons s) of
    (Nothing, mcs) -> maybe (property True) (expectFailure . eol) mcs
    (Just _,  mcs) -> maybe (property False) eol mcs
  where eol (c,s') = c === '\n' .||.
                     (c, fst <$> L8.uncons s') === ('\r', Just '\n')

scan :: L.ByteString -> Positive Int64 -> Property
scan s (Positive k) = parseBS p s === Just (toStrictBS $ L.take k s)
  where p = P.scan k $ \ n _ ->
            if n > 0 then let !n' = n - 1 in Just n' else Nothing

members :: [Word8] -> Property
members s = property $ all (`S.memberWord8` set) s
    where set = S.fromList s

nonmembers :: [Word8] -> [Word8] -> Property
nonmembers s s' = property . not . any (`S.memberWord8` set) $ filter (not . (`elem` s)) s'
    where set = S.fromList s

tests :: [Test]
tests = [
      testProperty "anyWord8" anyWord8
    , testProperty "endOfInput" endOfInput
    , testProperty "endOfLine" endOfLine
    , testProperty "notWord8" notWord8
    , testProperty "peekWord8" peekWord8
    , testProperty "peekWord8'" peekWord8'
    , testProperty "satisfy" satisfy
    , testProperty "satisfyWith" satisfyWith
    , testProperty "scan" scan
    , testProperty "skip" skip
    , testProperty "skipWhile" skipWhile
    , testProperty "string" string
    , testProperty "take" take
    , testProperty "takeByteString" takeByteString
    , testProperty "takeCount" takeCount
    , testProperty "takeLazyByteString" takeLazyByteString
    , testProperty "takeTill" takeTill
    , testProperty "takeWhile" takeWhile
    , testProperty "takeWhile1" takeWhile1
    , testProperty "takeWhile1_empty" takeWhile1_empty
    , testProperty "word8" word8
    , testProperty "members" members
    , testProperty "nonmembers" nonmembers
  ]
