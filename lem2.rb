require './lib/daru.rb'
require './lib/daru/version.rb'
require 'open-uri'
require './lib/daru/index/index.rb'
require './lib/daru/index/multi_index.rb'
require './lib/daru/index/categorical_index.rb'
require './lib/daru/helpers/array.rb'
require './lib/daru/vector.rb'
require './lib/daru/dataframe.rb'
require './lib/daru/monkeys.rb'
require './lib/daru/formatters/table'
require './lib/daru/iruby/helpers'
require './lib/daru/exceptions.rb'
require './lib/daru/core/group_by.rb'
require './lib/daru/core/query.rb'
require './lib/daru/core/merge.rb'
require './lib/daru/date_time/offsets.rb'
require './lib/daru/date_time/index.rb'

def main
  print "Please give me a filename: "
  filename = gets.chomp

  initial_table = file_to_array(filename: filename)
  @num_of_columns = initial_table.count
  data_table = reformat_table(initial_table)

  create_data_frame(data_table)

  @lem2_table = Daru::DataFrame.new
  build_attribute_value_pairs
  @goals = build_goals
  print_goals

  compute_rules

  return 0
end


# Move data from file to two dimensional array
# Global Variables
  # @num_of_attributes
def file_to_array(filename:)
  array = []
  file = File.open(filename).each_with_index do |line, idx|
    if idx == 0
      @num_of_attributes = line.scan(/a/).count
    else
      if idx == 1
        row = line.chomp.gsub(/\s+/m, ' ').gsub(']','').gsub('[','').strip.split(" ")
      else
        row = line.chomp.gsub(/\s+/m, ' ').strip.split(" ")
      end
        array << row
    end
  end
  array
end

# Format data by switching rows and columns to conform to Daru formatting
# Global Variables
  # @num_of_attributes
def reformat_table(arr)
  new_arr = []
  (0..@num_of_attributes).each do |idx|
    new_col = []
    arr.each do |value|
      new_col << value[idx]
    end
    new_arr << new_col
  end
  new_arr
end

# Create the Daru data frame object ( @df )
# Access each column's data by the Attribute name:
# ex. @df[:A].data.data returns an array of values for attribute A
# Global Variables
  # @df, DataFrame
  # @attributes_and_decision_name
def create_data_frame(arr)
  @df = Daru::DataFrame.new(arr)
  @attributes_and_decision_name = Daru::Index.new(@df.row[0].map { |x| x.to_sym })
  @df.vectors = @attributes_and_decision_name
  @df.delete_row(0)
end

# Global Variables
  # @df, DataFrame
  # @num_of_columns
def show_full_data
  (0...@num_of_columns).each do |num|
    print @df.row[num].data.data
    print "\n"
  end
end

# Global Variables
  # @attributes_and_decision_name
  # @lem2_table
def build_attribute_value_pairs
  arr = []
  last_index = @attributes_and_decision_name.count - 1
  @attributes_and_decision_name.each_with_index do |name, idx|
    if idx < last_index
      @df[name].data.data.uniq.each do |atr_val|
        arr << "(#{name.to_s}, #{atr_val})"
      end
    end
  end
  @lem2_table.add_vector(:a_v,arr)
  cases_arr = []
  num_of_cases_arr = []
  @lem2_table[:a_v].each do |attr_val|
    c = cases_for_attr_value_pair(attr_val: attr_val)
    cases_arr << c
    num_of_cases_arr << c.count
  end
  @lem2_table.add_vector(:cases,cases_arr)
  @lem2_table.add_vector(:num_of_cases,num_of_cases_arr)
end

# Global Variables
  # @attributes_and_decision_name
  # @df
def build_goals
  arr = []
  decision_name = @attributes_and_decision_name.at(@attributes_and_decision_name.count - 1)
  @df[decision_name].data.data.uniq.each do |dec_val|
    arr << "(#{decision_name.to_s}, #{dec_val})"
  end
  arr
end

# Global Variables
  # @goals
# Print all goals in the format "(Decision name, Decision value) : [valid cases]"
def print_goals
  puts "\n\nGOALS"
  puts "-----"
  @goals.each do |goal|
    puts "#{goal} : #{cases_for_goal_value_pair(goal_val: goal)}"
  end
end

# Global Variables
  # @df
# val will be a value for either an attribute or decision (ex. attributeVal pair (A, 0.8) should pass 0.8 into here)
# attr_val will be the attribute value pair (ex. "(A, 0.8)" )
def cases_for_attr_value_pair(attr_val:)
  cases_arr = []
  attribute_as_symbol = attr_val[/[^,]+/].gsub("(", "").to_sym # "(A, 0.8)" --> :A
  value = attr_val.partition(",").last.gsub(" ", "").gsub(")", "") # "(A, 0.8)" --> "0.8"
  @df[attribute_as_symbol].each_with_index do |val, idx|
    cases_arr << idx if val == value
  end
  cases_arr
end

# Global Variables
  # @df
def cases_for_goal_value_pair(goal_val:)
  cases_arr = []
  goal_as_symbol = goal_val[/[^,]+/].gsub("(", "").to_sym # "(D, V-Small)" --> :D
  value = goal_val.partition(",").last.gsub(" ", "").gsub(")", "") # "(A, 0.8)" --> "0.8"
  @df[goal_as_symbol].each_with_index do |val, idx|
    cases_arr << idx if val == value
  end
  cases_arr
end

# Global Variables
  # @lem2_table
# Adds a vector to the lem2_table including the union of each attribute value pair and the current goal
def create_goal_unions(goal:)
  goal_cases = cases_for_goal_value_pair(goal_val: goal)
  goal_union_array = grab_goal_attr_union(goal: goal, indices_to_not_include: [])
  @lem2_table.add_vector(goal_cases,goal_union_array)
end

def grab_goal_attr_union(goal:, indices_to_not_include:)
  if goal == "UseCurrentGoalCases"
    goal_cases = @current_goal_cases
  else
    goal_cases = cases_for_goal_value_pair(goal_val: goal)
  end
  goal_union_array = []
  @lem2_table[:a_v].each_with_index do |attr_val, idx|
    if indices_to_not_include.include?(idx)
      goal_union_array << []
    else
      union = []
      attr_cases = cases_for_attr_value_pair(attr_val: attr_val)
      union = attr_cases & goal_cases
      goal_union_array << union
    end
  end
  goal_union_array
end

def post_rule_grab_a_v_unions(goal_cases:)
  unions = []
  @lem2_table[:a_v].each_with_index do |attr_val, idx|
    union = []
    attr_cases = cases_for_attr_value_pair(attr_val: attr_val)
    union = attr_cases & goal_cases
    unions << union
  end
  unions
end


def index_with_max_number_of_cases(arr:)
  max_num_of_cases = 0
  max_index = 0
  arr.each do |idx|
    if @lem2_table[:num_of_cases].at(idx) > max_num_of_cases
      max_num_of_cases = @lem2_table[:num_of_cases].at(idx)
      max_index = idx
    end
  end
  max_index
end

def map_unions_for_current_goal(column:)
  maximum_coverage = 0
  attribute_value_index = 0
  column.map(&:any?).each_with_index do |has_union, idx|
    if has_union && (@lem2_table.data.last.at(idx).count > maximum_coverage)
      attribute_value_index = idx
      maximum_coverage = @lem2_table.data.last.at(idx).count
    end
  end
  indices = []
  column.each_with_index do |val, idx|
    indices << idx if @lem2_table.data.last.at(idx).count >= maximum_coverage
  end
  indices
end

def grab_best_possible_attr_val_pair_index
  comparison_column = @lem2_table.data.last # Most recent added goal union column
  indices = map_unions_for_current_goal(column: comparison_column)
  if indices.count > 1
    index_to_choose = index_with_max_number_of_cases(arr: indices)
  else
    index_to_choose = indices.first
  end
  index_to_choose
end

def compute_rules
  @rules = []
  @goals.each do |goal|
    find_rules_for_goal(goal: goal)
  end
  puts "\nFinal Rule Set\n"
  puts "--------------"
  puts @rules
  puts "\n"
end

def find_rules_for_goal(goal:)
  rule_found = false
  all_cases_covered = false
  attributes = []

  count = 0
  create_goal_unions(goal: goal) # Creates
  @current_goal_cases = cases_for_goal_value_pair(goal_val: goal)
  while(!all_cases_covered)
    while(!rule_found)
      # puts "\n#{count} time looping through\n"
      index_of_best_attr_val_pair = grab_best_possible_attr_val_pair_index # Index where attribute_value pair has the most cases
      # puts "index_of_best_attr_val_pair : #{index_of_best_attr_val_pair}"

      a_v_cases = grab_a_v_cases_and_unions(idx: index_of_best_attr_val_pair, other_indices: attributes)
      if a_v_cases.empty?
        # puts "*"*50 + "NOT VALID SEARCH"
        rule_found = true
        all_cases_covered = true
      end
      # puts "a_v_cases: #{a_v_cases}"
      goal_cases = cases_for_goal_value_pair(goal_val: goal)
      # puts "goal_cases: #{@current_goal_cases}"
      # puts "(a_v_cases - goal_cases): #{(a_v_cases - @current_goal_cases)}"
      if (a_v_cases - @current_goal_cases).empty? # If true, the attribute_value pair is a subset of our goal
        # puts "WE HAVE ENOUGH ATTRIBUTES"
        attributes << index_of_best_attr_val_pair
        attributes = attributes.uniq
        rule = []
        rule << [formatxyz(attrs: attributes, goal: goal), format_rule(attrs: attributes, goal: goal)]
        @rules << rule
        attributes = []
        # puts "@rules.count: #{@rules.count}"
        rule_found = true
        @current_goal_cases = @current_goal_cases - a_v_cases
        # puts "leftover_cases: #{@current_goal_cases}"
        if @current_goal_cases.empty?
          all_cases_covered = true # WE HAVE COVERED ALL CASES
        else
          # Change these two lines
          goal_union_array = post_rule_grab_a_v_unions(goal_cases: @current_goal_cases)
          @lem2_table.add_vector(@current_goal_cases,goal_union_array)
        end
      else # ADD ATTRIBUTE AND KEEP WORKING
        # puts "NEED MORE ATTRIBUTES"
        attributes << index_of_best_attr_val_pair
        attributes = attributes.uniq
        goal_union_array = grab_goal_attr_union(goal: "UseCurrentGoalCases", indices_to_not_include: attributes)
        # puts "goal_union_array: #{goal_union_array}"
        @lem2_table.add_vector(@current_goal_cases,goal_union_array)
      end
    end
    rule_found = false
  end
end

def grab_a_v_cases_and_unions(idx:, other_indices:)
  attribute_value_pairs_set = []
  if other_indices.empty?
    attribute_value_pairs_set = @lem2_table[:cases].at(idx) # attribute_value cases
  else
    attribute_value_pairs_set = @lem2_table[:cases].at(idx)
    other_indices.each do |index|
      attribute_value_pairs_set = attribute_value_pairs_set & @lem2_table[:cases].at(index)
    end
  end
  attribute_value_pairs_set
end

def format_rule(attrs:, goal:)
  attr_names = []
  attrs.each do |attr_idx|
    attr_names << @lem2_table[:a_v].at(attr_idx)
  end
  "#{attr_names.join(" & ")} -> #{goal}"
end

def formatxyz(attrs:, goal:)
  "(#{attrs.count}, #{strength(attrs: attrs, goal: goal)}, #{size_of_attribute_domain(attrs)})"
end

def strength(attrs:, goal:) # total number of correctly classified cases
 (cases_covered_by_attributes(attrs) & cases_covered_by_goal(goal)).count
end

def size_of_attribute_domain(attributes)
  cases_covered_by_attributes(attributes).count
end

def cases_covered_by_goal(goal)
  arr = []
  goal_name = goal.split(",")[0].gsub("(","")
  goal_val = goal.partition(",").last.gsub(")","").gsub(" ","")
  @df[goal_name.to_sym].each_with_index do |value, i|
    arr << i if goal_val == value
  end
  arr
end

def cases_covered_by_attributes(attrs)
  arr = []
  attrs.each do |attr_index|
    attr_val_pair = @lem2_table[:a_v].at(attr_index)
    attr_name = attr_val_pair.split(",")[0].gsub("(", "")
    attr_val = attr_val_pair.partition(",").last.gsub(")","").gsub(" ", "")
    @df[attr_name.to_sym].each_with_index do |value, i|
      arr << i if attr_val == value
    end
  end
  arr.uniq
end

main
