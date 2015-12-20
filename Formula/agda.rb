require "language/haskell"

class Agda < Formula
  include Language::Haskell::Cabal

  desc "Dependently typed functional programming language"
  homepage "http://wiki.portal.chalmers.se/agda/"
  revision 3

  stable do
    url "https://github.com/agda/agda/archive/2.4.2.4.tar.gz"
    sha256 "0147f8a1395a69bee1e7a452682094e45c83126233f9864544b8a14f956ce8c3"

    # fix compilation of the included Emacs mode
    # merged upstream in https://github.com/agda/agda/pull/1700
    patch :DATA

    resource "stdlib" do
      url "https://github.com/agda/agda-stdlib.git",
          :tag => "v0.11",
          :revision => "8602c29a7627eb001344cf50e6b74f880fb6bf18"
    end
  end

  bottle do
    sha256 "03fc9286e1f6a041208a8d836af0b5f68ee1c3c4995f6b26cee941c5a013908f" => :el_capitan
    sha256 "36fbd7f3195b7135fe7ded46f3bc2920f0078559db59cca07eb8f4a78ea3c034" => :yosemite
    sha256 "c448bc73d17adcfca1edfcdc2d361e3aa3f130cef9e50198c5463c66ca71effd" => :mavericks
  end

  head do
    url "https://github.com/agda/agda.git"

    resource "stdlib" do
      url "https://github.com/agda/agda-stdlib.git"
    end
  end

  option "without-stdlib", "Don't install the Agda standard library"
  option "without-malonzo", "Disable the MAlonzo backend"

  if build.with? "malonzo"
    depends_on "ghc"
  else
    depends_on "ghc" => :build
  end
  depends_on "cabal-install" => :build

  depends_on "gmp"
  depends_on :emacs => ["21.1", :recommended]

  setup_ghc_compilers

  def install
    # install Agda core
    cabal_sandbox do
      cabal_install_tools "alex", "happy", "cpphs"
      cabal_install "--only-dependencies"
      cabal_install "--prefix=#{prefix}"
    end
    cabal_clean_lib

    if build.with? "stdlib"
      resource("stdlib").stage lib/"agda"

      # generate the standard library's bytecode
      cd lib/"agda" do
        cabal_sandbox do
          cabal_install "--only-dependencies"
          cabal_install
          system "GenerateEverything"
        end
        rm_rf [".cabal", "dist"]
      end

      # install the standard library's FFI bindings for the MAlonzo backend
      # in a dedicated GHC package database
      if build.with? "malonzo"
        db_path = lib/"agda"/"ffi"/"package.conf.d"

        mkdir db_path
        system "ghc-pkg", "--package-db=#{db_path}", "recache"

        cd lib/"agda"/"ffi" do
          cabal_sandbox do
            system "cabal", "--ignore-sandbox", "install", "--package-db=#{db_path}",
              "--prefix=#{lib}/agda/ffi"
          end
          rm_rf [".cabal", "dist"]
        end
      end

      # generate the standard library's documentation and vim highlighting files
      cd lib/"agda" do
        system bin/"agda", "-i", ".", "-i", "src", "--html", "--vim", "README.agda"
      end
    end

    # compile the included Emacs mode
    if build.with? "emacs"
      system bin/"agda-mode", "compile"
      elisp.install_symlink Dir["#{share}/*/Agda-#{version}/emacs-mode/*"]
    end
  end

  def caveats
    s = ""

    if build.with? "stdlib"
      s += <<-EOS.undent
      To use the Agda standard library, point Agda to the following include dir:
        #{HOMEBREW_PREFIX}/lib/agda/src
      EOS

      if build.with? "malonzo"
        s += <<-EOS.undent

        To use the FFI bindings for the MAlonzo backend, give Agda the following option:
          --ghc-flag=-package-db=#{HOMEBREW_PREFIX}/lib/agda/ffi/package.conf.d
        EOS
      end
    end

    s
  end

  test do
    # run Agda's built-in test suite
    system bin/"agda", "--test"

    # typecheck and compile a simple module
    test_file_path = testpath/"simple-test.agda"
    test_file_path.write <<-EOS.undent
      {-# OPTIONS --without-K #-}
      module simple-test where
      open import Agda.Primitive
      infixr 6 _::_
      data List {i} (A : Set i) : Set i where
        [] : List A
        _::_ : A -> List A -> List A
      snoc : forall {i} {A : Set i} -> List A -> A -> List A
      snoc [] x = x :: []
      snoc (x :: xs) y = x :: (snoc xs y)
    EOS
    if build.with? "malonzo"
      system bin/"agda", "-c", "--no-main", "--safe", test_file_path
    end
    system bin/"agda", "--js", "--safe", test_file_path

    # typecheck, compile, and run a program that uses the standard library
    if build.with?("stdlib") && build.with?("malonzo")
      test_file_path = testpath/"stdlib-test.agda"
      test_file_path.write <<-EOS.undent
        module stdlib-test where
        open import Data.String
        open import Function
        open import IO
        main : _
        main = run $ putStr "Hello, world!"
      EOS
      system bin/"agda", "-i", testpath, "-i", lib/"agda"/"src",
        "--ghc-flag=-package-db=#{lib}/agda/ffi/package.conf.d",
        "-c", test_file_path
      assert_equal "Hello, world!", shell_output("#{testpath}/stdlib-test")
    end
  end
end

__END__
diff --git a/src/data/emacs-mode/agda2-mode.el b/src/data/emacs-mode/agda2-mode.el
index 04604ee..f6b3122 100644
--- a/src/data/emacs-mode/agda2-mode.el
+++ b/src/data/emacs-mode/agda2-mode.el
@@ -20,6 +20,7 @@ Note that the same version of the Agda executable must be used.")
 (require 'time-date)
 (require 'eri)
 (require 'annotation)
+(require 'fontset)
 (require 'agda-input)
 (require 'agda2)
 (require 'agda2-highlight)
