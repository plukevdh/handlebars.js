require "spec_helper"

describe "Parser" do
  let(:handlebars) { @context["Handlebars"] }

  def program(&block)
    ASTBuilder.build do
      program do
        instance_eval(&block)
      end
    end
  end

  def ast_for(string)
    ast = handlebars.parse(string)
    handlebars.print(ast)
  end

  class ASTBuilder
    def self.build(&block)
      ret = new
      ret.evaluate(&block)
      ret.out
    end

    attr_reader :out

    def initialize
      @padding = 0
      @out = ""
    end

    def evaluate(&block)
      instance_eval(&block)
    end

    def pad(string)
      @out << ("  " * @padding) + string + "\n"
    end

    def with_padding
      @padding += 1
      ret = yield
      @padding -= 1
      ret
    end

    def program
      pad("PROGRAM:")
      with_padding { yield }
    end

    def inverse
      pad("{{^}}")
      with_padding { yield }
    end

    def block
      pad("BLOCK:")
      with_padding { yield }
    end

    def inverted_block
      pad("INVERSE:")
      with_padding { yield }
    end

    def mustache(id, params = [], hash = nil)
      hash = " #{hash}" if hash
      pad("{{ #{id} [#{params.join(", ")}]#{hash} }}")
    end

    def partial(id, context = nil)
      content = id.dup
      content << " #{context}" if context
      pad("{{> #{content} }}")
    end

    def comment(comment)
      pad("{{! '#{comment}' }}")
    end

    def content(string)
      pad("CONTENT[ '#{string}' ]")
    end

    def string(string)
      string.inspect
    end

    def hash(*pairs)
      "HASH{" + pairs.map {|k,v| "#{k}=#{v}" }.join(", ") + "}"
    end

    def id(id)
      "ID:#{id}"
    end

    def path(*parts)
      "PATH:#{parts.join("/")}"
    end
  end

  it "parses simple mustaches" do
    ast_for("{{foo}}").should == program { mustache id("foo") }
  end

  it "parses mustaches with paths" do
    ast_for("{{foo/bar}}").should == program { mustache path("foo", "bar") }
  end

  it "parses mustaches with this/foo" do
    ast_for("{{this/foo}}").should == program { mustache id("foo") }
  end

  it "parses mustaches with parameters" do
    ast_for("{{foo bar}}").should == program { mustache id("foo"), [id("bar")] }
  end

  it "parses mustaches with hash arguments" do
    ast_for("{{foo bar=baz}}").should == program do
      mustache id("foo"), [], hash(["bar", "ID:baz"])
    end

    ast_for("{{foo bar=baz bat=bam}}").should == program do
      mustache id("foo"), [], hash(["bar", "ID:baz"], ["bat", "ID:bam"])
    end

    ast_for("{{foo bar=baz bat=\"bam\"}}").should == program do
      mustache id("foo"), [], hash(["bar", "ID:baz"], ["bat", "\"bam\""])
    end

    ast_for("{{foo omg bar=baz bat=\"bam\"}}").should == program do
      mustache id("foo"), [id("omg")], hash(["bar", id("baz")], ["bat", string("bam")])
    end
  end

  it "parses mustaches with string parameters" do
    ast_for("{{foo bar \"baz\" }}").should == program { mustache id("foo"), [id("bar"), string("baz")] }
  end

  it "parses contents followed by a mustache" do
    ast_for("foo bar {{baz}}").should == program do
      content "foo bar "
      mustache id("baz")
    end
  end

  it "parses a partial" do
    ast_for("{{> foo }}").should == program { partial id("foo") }
  end

  it "parses a partial with context" do
    ast_for("{{> foo bar}}").should == program { partial id("foo"), id("bar") }
  end

  it "parses a comment" do
    ast_for("{{! this is a comment }}").should == program do
      comment " this is a comment "
    end
  end

  it "parses an inverse section" do
    ast_for("{{#foo}} bar {{^}} baz {{/foo}}").should == program do
      block do
        mustache id("foo")

        program do
          content " bar "
        end

        inverse do
          content " baz "
        end
      end
    end
  end

  it "parses a standalone inverse section" do
    ast_for("{{^foo}}bar{{/foo}}").should == program do
      inverted_block do
        mustache id("foo")

        program do
          content "bar"
        end
      end
    end
  end

  it "raises if there's a Parse error" do
    lambda { ast_for("{{foo}") }.should   raise_error(V8::JSError, /Parse error on line 1/)
    lambda { ast_for("{{foo &}}")}.should raise_error(V8::JSError, /Parse error on line 1/)
  end

  it "knows how to report the correct line number in errors" do
    lambda { ast_for("hello\nmy\n{{foo}") }.should     raise_error(V8::JSError, /Parse error on line 3/m)
    lambda { ast_for("hello\n\nmy\n\n{{foo}") }.should raise_error(V8::JSError, /Parse error on line 5/m)
  end

  it "knows how to report the correct line number in errors when the first character is a newline" do
    lambda { ast_for("\n\nhello\n\nmy\n\n{{foo}") }.should raise_error(V8::JSError, /Parse error on line 7/m)
  end
end
