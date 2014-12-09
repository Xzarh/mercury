// vim: ts=4 sw=4 et

// The JavaInternal class in the jmercury.runtime package provides various
// Mercury runtime services that we may require.
// All Mercury runtime and generated Java code lives in the jmercury package.
//
import jmercury.runtime.JavaInternal;

// The mercury_lib class is generated by the compiler when we build
// mercury_lib library.
//
import jmercury.mercury_lib;

import static java.lang.System.out;

public class JavaMain {

    public static void main(String[] args)
    {
        // We do not need to do anything to initialise the Java version of the
        // Mercury runtime.  It will be automatically initialised as the
        // relevant classes are loaded by the JVM.

        out.println("JavaMain: start main");

        // This is a call to an exported Mercury procedure that does some I/O.
        // The mercury_lib class contains a static method for each procedure
        // that is foreign exported to Java.
        //
        mercury_lib.writeHello();

        // This is a call to an exported Mercury function.
        //
        out.println("3^3 = " + mercury_lib.cube(3));

        // When we have finished calling Mercury procedures then we need to
        // invoke any finalisers specified using ':- finalise' declarations in
        // the set of Mercury libraries we are using.
        // The static method run_finalisers() in the JavaInternal class does
        // this.  It will also perform any Mercury runtime finalisation that
        // may be needed.
        //
        JavaInternal.run_finalisers();

        // The Mercury exit status (as set by io.set_exit_status/1) may be read
        // from the static field 'exit_status' in the JavaInternal class.
        //
        out.println("JavaMain: Mercury exit status = "
            + JavaInternal.exit_status);

        out.println("JavaMain: end main");
   }
}