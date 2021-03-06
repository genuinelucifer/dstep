/**
 * Copyright: Copyright (c) 2011 Jacob Carlborg. All rights reserved.
 * Authors: Jacob Carlborg
 * Version: Initial created: Jan 29, 2012
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
 */
module dstep.translator.objc.ObjcInterface;

import mambo.core._;

import clang.c.Index;
import clang.Cursor;
import clang.Type;
import clang.Util;
import clang.Visitor;

import dstep.translator.Translator;
import dstep.translator.Declaration;
import dstep.translator.Output;
import dstep.translator.Type;

class ObjcInterface (Data) : Declaration
{
    ClassData currentClass;

    this (Cursor cursor, Cursor parent, Translator translator)
    {
        super(cursor, parent, translator);
    }

    override void translate (Output output)
    {
        auto cursor = cursor.objc;

        writeClass(output, spelling, cursor.superClass.spelling, collectInterfaces(cursor.objc), {
            foreach (cursor, parent ; cursor.declarations)
            {
                with (CXCursorKind)
                    switch (cursor.kind)
                    {
                        case CXCursor_ObjCInstanceMethodDecl:
                            translateMethod(cursor.func);
                            break;

                        case CXCursor_ObjCClassMethodDecl:
                            translateMethod(cursor.func, true);
                            break;

                        case CXCursor_ObjCPropertyDecl:
                            translateProperty(cursor);
                            break;

                        case CXCursor_ObjCIvarDecl:
                            translateInstanceVariable(cursor);
                            break;

                        default:
                            break;
                    }
            }
        });

        output.output(currentClass.data());
    }

    protected string[] collectInterfaces (ObjcCursor cursor)
    {
        string[] interfaces;

        foreach (cursor , parent ; cursor.protocols)
            interfaces ~= translateIdentifier(cursor.spelling);

        return interfaces;
    }

private:

    void writeClass (
        Output output,
        string name,
        string superClassName,
        string[] interfaces,
        void delegate () dg)
    {
        currentClass = new Data(translator.context);
        currentClass.name = translateIdentifier(name);
        currentClass.interfaces = interfaces;

        if (superClassName.isPresent)
            currentClass.superclass ~= translateIdentifier(superClassName);

        dg();
    }

    void translateMethod (
        FunctionCursor func,
        bool classMethod = false,
        string name = null)
    {
        import std.format : format;

        auto cls = currentClass;

        if (cls.propertyList.contains(func.spelling))
            return;

        name = cls.getMethodName(func, name, false);

        if (isGetter(func, name))
            translateGetter(func.resultType, name, cls, classMethod);

        else if (isSetter(func, name))
        {
            auto param = func.parameters.first;
            name = toDSetterName(name);
            translateSetter(param.type, name, cls, classMethod, param.spelling);
        }

        else
        {
            Output output = new Output();
            
            translateFunction(output, translator.context, func, name, classMethod),
            output.append(" ");
            writeSelector(output, func.spelling);
            output.append(";");

            cls.members ~= output;
        }
    }

    void translateProperty (Cursor cursor)
    {
        auto cls = currentClass;
        auto name = cls.getMethodName(cursor.func, "", false);

        translateGetter(cursor.type, name, cls, false);
        translateSetter(cursor.type, name, cls, false);
    }

    void translateInstanceVariable (Cursor cursor)
    {
        Output output = new Output();
        translator.variable(output, cursor);
        currentClass.instanceVariables ~= output;
    }

    void translateGetter (Type type, string name, ClassData cls, bool classMethod)
    {
        import std.format : format;

        auto dName = name == "class" ? name : translateIdentifier(name);

        Output output = new Output();

        output.singleLine(
            "@property %s%s %s () ",
            classMethod ? "static " : "",
            translateType(translator.context, type),
            dName);

        writeSelector(output, name);
        output.append(";");

        cls.members ~= output;
        cls.propertyList.add(name);
    }

    void translateSetter (Type type, string name, ClassData cls, bool classMethod, string parameterName = "")
    {
        import std.format : format;

        auto selector = toObjcSetterName(name) ~ ':';

        Output output = new Output();

        output.singleLine(
            "@property %svoid %s (%s",
            classMethod ? "static " : "",
            translateIdentifier(name),
            translateType(translator.context, type));

        if (parameterName.any)
            output.append(" %s", parameterName);

        output.append(") ");
        writeSelector(output, selector);
        output.append(";");

        cls.members ~= output;
        cls.propertyList.add(selector);
    }

    string toDSetterName (string name)
    {
        assert(isSetter(name));
        name = name[3 .. $];
        auto firstLetter = name[0 .. 1];
        auto r = firstLetter.toLower ~ name[1 .. $];
        return r.assumeUnique;
    }

    string toObjcSetterName (string name)
    {
        auto r = "set" ~ name[0 .. 1].toUpper ~ name[1 .. $];
        return r.assumeUnique;
    }

    bool isGetter (FunctionCursor cursor, string name)
    {
        return cursor.resultType.kind != CXTypeKind.CXType_Void && cursor.parameters.isEmpty;
    }

    bool isSetter (string name)
    {
        if (name.length > 3 && name.startsWith("set"))
        {
            auto firstLetter = name[3 .. $].first;
            return firstLetter.isUpper;
        }

        return false;
    }

    bool isSetter (FunctionCursor cursor, string name)
    {
        return isSetter(name) &&
            cursor.resultType.kind == CXTypeKind.CXType_Void &&
            cursor.parameters.length == 1;
    }

    void writeSelector (Output output, string selector)
    {
        import std.format : format;
        output.append(`@selector("%s")`, selector);
    }
}
