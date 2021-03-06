-- |
-- Module      : System.X509
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unix only
--
-- this module is portable to unix system where there is usually
-- a /etc/ssl/certs with system X509 certificates.
--
-- the path can be dynamically override using the environment variable
-- defined by envPathOverride in the module, which by
-- default is SYSTEM_CERTIFICATE_PATH
--
module System.X509.Unix
    ( getSystemCertificateStore
    ) where

import System.Directory (getDirectoryContents, doesFileExist, doesDirectoryExist)
import System.Environment (getEnv)
import System.FilePath ((</>))

import Data.List (isPrefixOf)
import Data.PEM (PEM(..), pemParseBS)
import Data.Either
import qualified Data.ByteString as B
import Data.X509
import Data.X509.CertificateStore

import Control.Applicative ((<$>))
import Control.Monad (filterM)
import qualified Control.Exception as E

import Data.Char

defaultSystemPaths :: [FilePath]
defaultSystemPaths =
    [ "/etc/ssl/certs/"                 -- linux
    , "/system/etc/security/cacerts/"   -- android
    , "/usr/local/share/certs/"         -- freebsd
    , "/etc/ssl/cert.pem"               -- openbsd
    ]

envPathOverride :: String
envPathOverride = "SYSTEM_CERTIFICATE_PATH"

listDirectoryCerts :: FilePath -> IO (Maybe [FilePath])
listDirectoryCerts path = do
    isDir  <- doesDirectoryExist path
    isFile <- doesFileExist path
    if isDir
        then (fmap (map (path </>) . filter isCert) <$> getDirContents)
             >>= maybe (return Nothing) (\l -> Just <$> filterM doesFileExist l)
        else if isFile then return $ Just [path] else return Nothing
    where isHashedFile s = length s == 10
                        && isDigit (s !! 9)
                        && (s !! 8) == '.'
                        && all isHexDigit (take 8 s)
          isCert x = (not $ isPrefixOf "." x) && (not $ isHashedFile x)

          getDirContents = E.catch (Just <$> getDirectoryContents path) emptyPaths
            where emptyPaths :: E.IOException -> IO (Maybe [FilePath])
                  emptyPaths _ = return Nothing

getSystemCertificateStore :: IO CertificateStore
getSystemCertificateStore = makeCertificateStore <$> (getSystemPaths >>= findFirst)
  where findFirst [] = return []
        findFirst (p:ps) = do
            r <- listDirectoryCerts p
            case r of
                Nothing    -> findFirst ps
                Just []    -> findFirst ps
                Just files -> concat <$> mapM readCertificates files

getSystemPaths :: IO [FilePath]
getSystemPaths = E.catch ((:[]) <$> getEnv envPathOverride) inDefault
    where
        inDefault :: E.IOException -> IO [FilePath]
        inDefault _ = return defaultSystemPaths

readCertificates :: FilePath -> IO [SignedCertificate]
readCertificates file = E.catch (either (const []) (rights . map getCert) . pemParseBS <$> B.readFile file) skipIOError
    where
        getCert = decodeSignedCertificate . pemContent
        skipIOError :: E.IOException -> IO [SignedCertificate]
        skipIOError _ = return []
