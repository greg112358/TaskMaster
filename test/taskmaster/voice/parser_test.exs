defmodule Taskmaster.Voice.ParserTest do
  use ExUnit.Case, async: true

  alias Taskmaster.Voice.Parser

  describe "a time of day in what was said" do
    test "is split off the title" do
      assert {:add_event, %{title: "dentist", start_time: ~T[15:00:00]}} =
               Parser.parse("add event dentist at 3pm")
    end

    test "reads minutes and a spaced meridiem" do
      assert {:add_event, %{title: "dentist", start_time: ~T[15:30:00]}} =
               Parser.parse("add event dentist at 3:30 pm")
    end

    test "reads the meridiem however the recogniser punctuates it" do
      assert {:add_event, %{start_time: ~T[00:00:00]}} =
               Parser.parse("add event lunch at 12 a.m.")

      assert {:add_event, %{start_time: ~T[12:00:00]}} = Parser.parse("add event lunch at 12 pm")
    end

    test "reads noon and midnight" do
      assert {:add_task, %{start_time: ~T[12:00:00]}} = Parser.parse("add task bins at noon")
      assert {:add_task, %{start_time: ~T[00:00:00]}} = Parser.parse("add task bins at midnight")
    end

    test "reads a 24-hour clock" do
      assert {:add_event, %{title: "standup", start_time: ~T[14:30:00]}} =
               Parser.parse("add event standup at 14:30")
    end

    test "rides along with a recurrence rule" do
      assert {:add_task,
              %{
                title: "bins",
                person_name: "greg",
                start_time: ~T[07:00:00],
                recurrence_type: "weekly"
              }} = Parser.parse("add task for greg bins at 7 am every week")
    end

    # Half past seven means either half of the day, and the recogniser writes
    # "7:30 PM" whenever the speaker actually said one. A guess here is stored
    # and then has to be found and corrected.
    test "an hour with no am or pm is left in the title" do
      assert {:add_event, %{title: "dinner at 7:30", start_time: nil}} =
               Parser.parse("add event dinner at 7:30")
    end

    test "an impossible time is left in the title" do
      assert {:add_event, %{title: "dentist at 25:00", start_time: nil}} =
               Parser.parse("add event dentist at 25:00")
    end

    test "a title that merely contains at keeps it" do
      assert {:add_event, %{title: "meet greg at the park", start_time: nil}} =
               Parser.parse("add event meet greg at the park")
    end

    test "nothing spoken about time is no time" do
      assert {:add_task, %{title: "vacuum", start_time: nil}} = Parser.parse("add task vacuum")
    end
  end

  describe "the person a task is for" do
    test "is read off for <name>" do
      assert {:add_task, %{title: "vacuum", person_name: "greg"}} =
               Parser.parse("add task for greg vacuum")
    end

    # An optional capture group that did not participate is "", and "" is
    # truthy: read as a name it sent every unassigned task down the "Unknown
    # person:" path instead of adding it.
    test "is nil when nobody was named" do
      assert {:add_task, %{person_name: nil}} = Parser.parse("add task vacuum")
      assert {:add_task, %{person_name: nil}} = Parser.parse("add task vacuum every week")
    end
  end

  describe "the rest of the grammar" do
    test "navigation" do
      assert Parser.parse("show groceries") == {:navigate, :groceries}
      assert Parser.parse("show calendar") == {:navigate, :calendar}
      assert Parser.parse("show chores") == {:navigate, :chores}
    end

    test "groceries" do
      assert Parser.parse("add milk to groceries") == {:add_grocery, "milk"}
      assert Parser.parse("clear groceries") == :clear_groceries
    end

    test "recurrence rules" do
      assert {:add_task, %{recurrence_type: "every_n_weeks", recurrence_interval: 2}} =
               Parser.parse("add task clean cat tree every 2 weeks")

      assert {:add_event, %{recurrence_type: "yearly"}} =
               Parser.parse("add event birthday every year")
    end

    test "anything else" do
      assert Parser.parse("what is the weather") == :unrecognized
    end
  end
end
