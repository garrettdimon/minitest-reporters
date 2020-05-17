module Minitest
  module Reporters
    # A reporter focused on a "don't make me think" approach that emphasizes
    # which areas need the most attention.
    #
    # It prioritizes results by giving the most visual importance to the most
    # significant problems. For instance, when there are exceptions or failures,
    # it doesn't show skipped tests or performance information.
    #
    # It also groups errors based on file so that it can present a summary of
    # the most problematic files at the end.

    class FocusReporter < BaseReporter
      include RelativePosition

      BLACK         = '0;30'
      RED           = '0;31'
      GREEN         = '0;32'
      BROWN         = '0;33'
      BLUE          = '0;34'
      PURPLE        = '0;35'
      CYAN          = '0;36'
      GRAY          = '0;37'
      DARK_GRAY     = '1;30'
      LIGHT_RED     = '1;31'
      LIGHT_GREEN   = '1;32'
      YELLOW        = '1;33'
      LIGHT_BLUE    = '1;34'
      LIGHT_PURPLE  = '1;35'
      LIGHT_CYAN    = '1;36'
      WHITE         = '1;37'
      BOLD          = '1'
      NOT_BOLD      = '21'

      def initialize(options = {})
        super
        @detailed_skip = options.fetch(:detailed_skip, true)
        @show_test_command = options.fetch(:command, true)
        @fast_fail = options.fetch(:fast_fail, false)
        @color = options.fetch(:color, true)
        @slow_suite_threshold = options.fetch(:slow_suite_threshold, 1.0)
        @slow_suite_count = options.fetch(:slow_suite_count, 3)
        @slow_threshold = options.fetch(:slow_threshold, 0.5)
        @slow_count = options.fetch(:slow_count, 3)
        @options = options
        @suite_times = []
        @suite_start_times = {}
      end

      def start
        super
        on_start
      end

      def on_start
        # Blank line for whitespace and readability.
        puts
        # puts("# Running tests with run options %s:" % options[:args])
        # puts
      end

      def before_test(test)
        super
        print "\n#{test.class}##{test.name} " if options[:verbose]
      end

      def before_suite(suite)
        @suite_start_times[suite] = Minitest::Reporters.clock_time
        super
      end

      def after_suite(suite)
        super
        duration = suite_duration(suite)
        @suite_times << [suite.name, duration]
      end

      def record(test)
        super

        on_record(test)
      end

      def on_record(test)
        print "#{"%.2f" % test.time} = " if options[:verbose]

        # Print the pass/skip/fail mark
        result_code = if test.passed?
                        pass(test.result_code)
                      elsif test.skipped?
                        skip(test.result_code)
                      elsif test.error?
                        error(test.result_code)
                      elsif test.failure
                        failure(test.result_code)
                      end

        print result_code

        # Print fast_fail information
        if @fast_fail && (test.skipped? || test.failure)
          print_failure(test)
        end
      end

      def report
        super
        on_report
      end
      alias :to_s :report

      def on_report
        puts
        puts
        failures_summary
        counts_summary
        performance_summary
        slow_tests_summary
        slow_suite_summary
        test_problem_areas_summary
        code_problem_areas_summary
        skipped_summary

        # Prints a color reference for context
        # color_options_summary
      end

      def print_failure(test)
        return if test.skipped? && big_problems?

        message = message_for(test)
        unless message.nil? || message.strip == ''
          puts colored_for(result(test), message)
          puts
        end
      end

      private

        # Prints each of the failed tests
        def failures_summary
          return if @fast_fail

          failed_tests.each do |test|
            print_failure(test)
          end
        end

        # Gives a nicely formatted view of skipped tests
        def skipped_summary
          return if @fast_fail || skipped_tests.empty? || big_problems?

          skipped_lines = {}

          skipped_tests.each do |test|
            test_file = test.source_location[0].gsub(Dir.pwd, '').gsub('/test/', '')
            test_line = test.source_location[1]

            if skipped_lines.has_key? test_file
              skipped_lines[test_file] << test_line
            else
              skipped_lines[test_file] = [test_line]
            end
          end

          skipped_lines.reject! { |location, count| count.size == 1 }

          if skipped_lines.any?
            problem_files = skipped_lines
                          .sort_by { |location, count| location }
                          .sort_by { |location, count| count.size }
                          .reverse
                          .take(3)

            puts skip('Skipped Tests:')
            problem_files.each do |path, line_numbers|
              count = line_numbers.size
              line_numbers.sort!

              print skip(count.to_s + " ")
              print gray(path)
              puts dark_gray(" › " + line_numbers.join(' ') + " › rails test #{path}")
            end
            puts
          end
        end

        # Gives a list of test files with the most issues sorted by issue count
        # and also provides the rails command to run the tests in just that file
        def test_problem_areas_summary
          return unless big_problems?

          test_lines = {}

          failed_tests.each do |test|
            test_file = test.source_location[0].gsub(Dir.pwd, '').gsub('/test/', '')
            test_line = test.source_location[1]

            if test_lines.has_key? test_file
              test_lines[test_file] << test_line
            else
              test_lines[test_file] = [test_line]
            end
          end

          test_lines.reject! { |location, count| count.size == 1 }

          if test_lines.any?
            problem_files = test_lines
                          .sort_by { |location, count| location }
                          .sort_by { |location, count| count.size }
                          .reverse
                          .take(3)

            puts failure('Problematic Files:')
            problem_files.each do |path, line_numbers|
              count = line_numbers.size

              line_numbers.sort!

              print white(count.to_s + " ")
              print gray(path)
              puts dark_gray(" › " + line_numbers.join(' ') + " › rails test #{path}")
            end
            puts
          end
        end

        # Gives a nicely formatted summary of the lines of code that showed up
        # more than once in any problematic tests
        def code_problem_areas_summary
          return unless big_problems?

          failure_bits = {}

          failed_tests.each do |test|
            failure_file = test.failure.location.gsub(Dir.pwd, '').gsub('/test/', '')
            failure_message = test.failure.message

            if failure_bits.has_key? failure_file
              failure_bits[failure_file][:count] += 1
            else
              failure_bits[failure_file] = {
                count: 1,
                message: failure_message
              }
            end
          end

          failure_bits.reject! { |location, value| value[:count] == 1 }

          if failure_bits.any?
            problem_files = failure_bits
                          .sort_by { |location, value| location }
                          .reverse
                          .sort_by { |location, value| value[:count] }
                          .reverse
                          .take(3)


            puts error('Problematic Lines of Code:')
            problem_files.each do |path, value|
              print white(value[:count].to_s + " ")
              puts gray(path)
              puts dark_gray("#{value[:message]}")
              puts
            end
          end
        end

        # Provides a high-level performance summary of the full test suite
        def performance_summary
          total_duration = "%.2fs " % [total_time]
          average_durations = "(%.2f tests/s, %.2f assertions/s)" %
                        [count / total_time, assertions / total_time]

          print white(total_duration)
          puts dark_gray(average_durations)
          puts
        end

        # Provides counts for failures, errors, and skips if there are any
        def counts_summary
          tests_summary     = '%d tests & %d assertions' % [count, assertions]
          failures_summary  = failures? ? failure("#{failures} failures.") : nil
          errors_summary    = errors? ? error("#{errors} errors.") : nil
          skips_summary     = skips? ? skip("#{skips} skips.") : nil

          puts [failures_summary, errors_summary, skips_summary].compact.join(' ')
          puts colored_for(suite_result, tests_summary)
        end

        # Takes the top @slow_count tests and displays them
        def slow_tests_summary
          return if @slow_count.zero? || big_problems? || skips?

          slow_tests = tests
                        .sort_by(&:time)
                        .reverse
                        .take(@slow_count)
                        .delete_if {|t| t.time < @slow_threshold }
          # #<Minitest::Result:0x00007fd90e45afa8 @NAME="test_should_get_edit_plan_page", @failures=[], @assertions=1, @klass="PlansControllerTest", @time=0.14770399988628924, @source_location=["/Users/garrettdimon/Work/fireside/test/controllers/plans_controller_test.rb", 21]>
          if slow_tests.any?
            slow_tests.each do |test|
              test_time = "%.2fs" % [test.time]
              test_name = " %s - %s" % [test.klass, test.name.gsub('_', ' ').gsub('test ', '')]
              test_location = "      %s:%s" % [test.source_location[0].gsub(Dir.pwd, ''), test.source_location[1]]

              print white(test_time)
              puts test_name
              puts dark_gray(test_location)
            end
          end
          puts
        end

        def slow_suite_summary
          return if @slow_suite_count.zero? || big_problems? || skips?

          # puts @suite_times.inspect

          slow_suites = @suite_times
                          .sort_by { |x| x[1] }
                          .reverse
                          .take(@slow_suite_count)
                          .delete_if {|t| t[1] < @slow_suite_threshold }

          slow_suites.each do |slow_suite|
            test_time = "%.2fs " % [slow_suite[1]]
            suite = slow_suite[0]
            print white(test_time)
            puts suite
          end
          puts
        end

        def color_options_summary
          puts
          puts "-----------------"
          %w{white gray dark_gray black red light_red purple light_purple blue light_blue cyan light_cyan green light_green brown yellow }.each do |c|
            puts send(c.to_sym, c)
          end
          puts "-----------------"
          puts
        end

        def relative_path(path)
          Pathname.new(path).relative_path_from(Pathname.new(Dir.getwd))
        end

        def get_source_location(result)
          if result.respond_to? :klass
            result.source_location
          else
            result.method(result.name).source_location
          end
        end

        def color?
          return @color if defined?(@color)
          @color = @options.fetch(:color) do
            io.tty? && (
              ENV["TERM"] =~ /^screen|color/ ||
              ENV["EMACS"] == "t"
            )
          end
        end

        def colored_for(result, string)
          send(result, string)
        end

        def failures?
          failures > 0
        end

        def errors?
          errors > 0
        end

        def skips?
          skips > 0
        end

        # Effectively a flag for "we've got bigger things to worry about than skipped tests or performance"
        def big_problems?
          failures? || errors?
        end

        # Determines the most significant level of issues for the suite as a
        # whole in order to determine the the color to use for the suite summary
        def suite_result
          case
          when failures > 0; :failure
          when errors > 0; :error
          when skips > 0; :skip
          else :pass
          end
        end

        def failed_tests
          tests.reject(&:passed?)
        end

        def skipped_tests
          tests.select(&:skipped?)
        end

        def location(exception)
          last_before_assertion = ''
          exception.backtrace.reverse_each do |s|
            break if s =~ /in .(assert|refute|flunk|pass|fail|raise|must|wont)/
            last_before_assertion = s
          end

          last_before_assertion.sub(/:in .*$/, '')
        end

        def command_to_rerun_test(test)
          location = get_source_location(test)
          "rails test #{relative_path(location[0])}:#{location[1]}"
        end

        def message_for(test)
          e = test.failure
          test_name = test.name.gsub('test_', '').gsub('_', ' ')
          message = dark_gray(test.failure.message)
          error_class = dark_gray("#{test.failure.class}:")
          affected_class = test_class(test)
          failure_location = gray(test.failure.location.gsub(Dir.pwd, '').gsub('/test/', ''))
          test_command = dark_gray(" › " + command_to_rerun_test(test))

          if test.skipped?
            "Skipped › #{affected_class} · #{test_name}\n#{failure_location}#{test_command}\n#{message}"
          elsif test.error?
            "Error › #{affected_class} · #{test_name}\n#{failure_location}#{test_command}\n#{error_class}\n#{message}"
          else
            "Failure › #{affected_class} · #{test_name}\n#{failure_location}#{test_command}\n#{error_class}\n#{message}"
          end
        end

        def suite_duration(suite)
          start_time = @suite_start_times.delete(suite)
          if start_time.nil?
            0
          else
            Minitest::Reporters.clock_time - start_time
          end
        end

        def formatify(string, modifier)
          color? ? "\e\[#{ modifier }m#{ string }\e[0m" : string
        end

        def bold(string)
          formatify(string, BOLD)
        end

        def black(string)
          formatify(string, BLACK)
        end

        def red(string)
          formatify(string, RED)
        end
        alias :fail :red
        alias :failed :red
        alias :failure :red

        def green(string)
          formatify(string, GREEN)
        end

        def brown(string)
          formatify(string, BROWN)
        end

        def blue(string)
          formatify(string, BLUE)
        end

        def purple(string)
          formatify(string, PURPLE)
        end

        def cyan(string)
          formatify(string, CYAN)
        end

        def gray(string)
          formatify(string, GRAY)
        end

        def dark_gray(string)
          formatify(string, DARK_GRAY)
        end
        alias :meta :dark_gray

        def light_red(string)
          formatify(string, LIGHT_RED)
        end
        alias :error :light_red

        def light_green(string)
          formatify(string, LIGHT_GREEN)
        end
        alias :success :light_green
        alias :succeed :light_green
        alias :pass :light_green

        def yellow(string)
          formatify(string, YELLOW)
        end
        alias :skip :yellow

        def light_blue(string)
          formatify(string, LIGHT_BLUE)
        end

        def light_purple(string)
          formatify(string, LIGHT_PURPLE)
        end

        def light_cyan(string)
          formatify(string, LIGHT_CYAN)
        end

        def white(string)
          formatify(string, WHITE)
        end

    end
  end
end
