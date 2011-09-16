module System.Build.ManningBook.Build where

import System.Build.ManningBook.Config
import Codec.Archive.Zip
import qualified Data.ByteString.Lazy as L
import System.FilePath.FilePather
import qualified System.FilePath.FilePather as P
import System.FilePath
import System.Directory
import System.Command
import Control.Monad
import Control.Monad.Writer
import System.IO
import Network.HTTP.Enumerator
import Data.Enumerator.Binary
import Data.Enumerator hiding (sequence)

downloadDependencyIfNotAlready ::
  FilePath
  -> Configer String
  -> ConfIO Bool
downloadDependencyIfNotAlready f g =
  ConfigerT $ \c ->
    let d = dependencyDirectory c
        p = d </> f
    in WriterT $
         do e <- doesFileExist p
            if e
              then
                return (True, return $ "Dependency " ++ p ++ " already exists")
              else
                do createDirectoryIfMissing True d
                   withFile p WriteMode $ \h ->
                     do let u = g =>>> c
                        r <- parseUrl u
                        withManager $ run_ . httpRedirect r (\_ _ -> iterHandle h)
                        return (False, return $ "Retrieved dependency " ++ p ++ " from " ++ show u)

mkdir ::
  FilePath
  -> Log IO ()
mkdir d =
  WriterT $
    do createDirectoryIfMissing True d
       return ((), return $ "Created directory " ++ d)

aavalidatorDownload ::
  ConfIO Bool
aavalidatorDownload =
  do x <- downloadDependencyIfNotAlready "AAValidator.zip" aavalidator
     _ <- unless x . ConfigerT $ \c ->
                       let d = dependencyDirectory c </> "AAValidator"
                       in do _ <- mkdir d
                             indir d (\z -> L.readFile (z </> dependencyDirectory c </> "AAValidator.zip") >>=
                                            extractFilesFromArchive (zipOptions c) . toArchive) ++> ("Extract files from archive in directory " ++ d)
     return x

aamakepdfDownload ::
  ConfIO Bool
aamakepdfDownload =
  do x <- downloadDependencyIfNotAlready "AAMakePDF.zip" aamakepdf
     _ <- unless x . ConfigerT $ \c ->
                       let d = dependencyDirectory c </> "AAMakePDF"
                       in do _ <- mkdir d
                             indir d (\z -> L.readFile (z </> dependencyDirectory c </> "AAMakePDF.zip") >>=
                                            extractFilesFromArchive (zipOptions c) . toArchive) ++> ("Extract files from archive in directory " ++ d)
     return x

docbookindexerDownload ::
  ConfIO Bool
docbookindexerDownload =
  do x <- downloadDependencyIfNotAlready "docbookIndexer.zip" docbookindexer
     _ <- unless x . ConfigerT $ \c ->
                       let lib = dependencyDirectory c
                       in indir lib (\z -> L.readFile (z </> dependencyDirectory c </> "docbookIndexer.zip") >>=
                                           extractFilesFromArchive (zipOptions c) . toArchive) ++> ("Extract files from archive in directory " ++ lib)
     return x

pdfmakerDownload ::
  ConfIO Bool
pdfmakerDownload =
  downloadDependencyIfNotAlready "pdfmaker.xsl" pdfmaker

allDownload ::
  ConfIO [Bool]
allDownload =
  sequence [
    aavalidatorDownload
  , aamakepdfDownload
  , docbookindexerDownload
  , pdfmakerDownload
  ]

mkDistDir ::
  ConfIO ()
mkDistDir =
  ConfigerT $
    mkdir . distDir

pdf ::
  CLog IO ([Bool], ExitCode)
pdf =
  do h <- allDownload
     _ <- mkDistDir
     i <- ConfigerT $ \c ->
            indir (dependencyDirectory c </> "AAMakePDF")
                   (\d -> system $ unwords [
                                             "java"
                                           , "-Djava.ext.dirs=" ++ dependencyDirectory c
                                           , "AAPDFMaker"
                                           , d </> src c
                                           , d </> distDir c </> "fpinscala.pdf"
                                           ]) ++> "Generate PDF"
     _ <- ConfigerT $ \c ->
            let junk = src c ++ ".temp.xml"
            in ((doesFileExist junk >>= \k -> k `when` removeFile junk) ++> ("Removing junk file " ++ junk))
     return (h, i)

 {-
validate ::
  Config
  -> IO ExitCode
validate c =
  withDependencies c $
  exitWith' $ indir (lib </> "AAValidator") $ \d ->
       (system' c $ unwords [
                              "java"
                            , "-classpath"
                            , intercalate [searchPathSeparator] ["AAValidator.jar", "svnkit.jar", "servlet.jar", "maven-embedder-2.0.4-dep.jar", "maven-2.0.9-uber.jar"]
                            , "AAValidator"
                            , d </> indexFile
                            ]) <* removeFileIfExists (d </> src </> "temp.xml")
-}

jarFiles ::
  FilePath
  -> IO [FilePath]
jarFiles =
  P.find always (extensionEq "jar")