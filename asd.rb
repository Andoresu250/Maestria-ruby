require 'google_maps_service'
require 'http'
require 'certified'
require 'csv'
require 'console_view_helper'
require 'benchmark'
# ---------------------- Classes ---------------------- #
class FileToNodes

  def self.getNodes(route)
    data = {}
    nodes = []
    data[:sample] = '001'
    data[:vehicles_number] = 25
    data[:capacity] = 200
    csv_places = CSV.read(route)
    labels = csv_places.map {|place| place.join(", ")}
    labels.delete(labels.first)

    labels.each do |label|
      nodes << label.split(';')
    end

    data[:nodes] = nodes
    data
  end
end

class Node
  attr_accessor :id, :place, :demand, :ready_time, :due_time, :service_time

  def initialize(id, place, demand, ready_time, due_time, service_time)
    @id, @place = id.to_i, place
    @demand, @ready_time, @due_time = demand.to_i, Time.utc(2016,9,1,ready_time.split(":")[0].to_i,ready_time.split(":")[1].to_i), Time.utc(2016,9,1,due_time.split(":")[0].to_i,due_time.split(":")[1].to_i)
    @service_time = service_time.to_i    
  end  

  def calculate_time(node, time)
    origins = [@place]
    destinations = [node.place]    
    gmaps = GoogleMapsService::Client.new
    matrix = gmaps.distance_matrix(origins, destinations,
        mode: 'driving',
        language: 'es-co',    
        units: 'metric',
        departure_time: time )
    p "A: #{origins[0]} b: #{destinations[0]} distance: #{matrix[:rows][0][:elements][0][:duration_in_traffic][:value]}"
    matrix[:rows][0][:elements][0][:duration_in_traffic][:value].to_f
  end

end

class NodesManager

  attr_accessor :nodes, :origin, :unvisited

  def initialize(nodes)
    @nodes = []
    load_nodes(nodes)    
    @origin = @nodes.first
    @nodes = @nodes.sort_by { |node| node.due_time }
    @unvisited = @nodes.clone
    @unvisited.delete(@origin)
  end

  def find_node(id)
    @nodes.select { |node| node.id == id }.first
  end

  private
  def load_nodes(nodes)
    nodes.each do |node|
      @nodes << Node.new(node[0], node[1], node[2], node[3], node[4], node[5])
    end
  end  
end


class Route

  attr_accessor :route, :arrival_time, :wait_time, :services_time, :total_distance, :demand, :total_service_time, :current_time

  def initialize criterion, capacity
    @current_time = Time.utc(2016,9,6,6,0)
    @route = []
    @arrival_time = Time.utc(2016,9,6,6,0)
    @wait_time = @services_time = @total_distance = @total_service_time = 0
    @demand = capacity
    add $nodesManager.origin
    seed criterion
    add $nodesManager.origin
    split_routes.each do |split|
      assign_values calculate_values(split[0], split[1])
    end
  end

  def seed(criterion)
    case criterion
      when 1
        add criterion_1
      when 2
        add criterion_2
    end
  end

  # Get the times between two nodes
  def calculate_values(node_i, node_j, object = self)
    values = {}
    wik = node_i == $nodesManager.origin ? node_i.ready_time : object.services_time

    distance = node_i.calculate_time(node_j, object.current_time)    
    values[:arrival_time]  = wik + node_i.service_time + distance
    wait_time = ready_time(node_j, values[:arrival_time])

    demand = object.demand - node_i.demand
    if wait_time && demand >= 0
      values[:distance] = distance
      values[:wait_time] = wait_time
      values[:services_time] = values[:arrival_time] + wait_time
      values[:total_service_time] = node_i.service_time
      object.demand = demand
      object.current_time += (distance + wait_time + node_i.service_time)
      values
    else
      false
    end
  end

  # insert a node and calculate times for the new potencial route
  def insert_node(node, position)
    add(node, position)
    split_routes.each do |split|
      values = calculate_values(split[0], split[1])
      if values
        assign_values(values)
      else
        return false
      end
    end
  end

  def calculate_c2(node, position_node, original_route, constant)

    previous_node = @route[position_node - 1]
    next_node = @route[position_node + 1]

    c11 = previous_node.calculate_time(node, @current_time) + node.calculate_time(next_node, @current_time) - (RoutesManager::VARIATIONS[constant][:m] * previous_node.calculate_time(next_node, @current_time))

    route_original_c12 = original_route.route[0..position_node]
    route_alternative_c12 = self.route[0..position_node + 1]


    copy_original = original_route.clone
    copy_original.reset_attributes(copy_original)
    copy_alternative = self.clone
    copy_alternative.reset_attributes(copy_alternative)

    split_routes(route_original_c12).each do |split|
      assign_values(calculate_values(split[0], split[1], copy_original), copy_original)
    end
    split_routes(route_alternative_c12).each do |split|
      assign_values(calculate_values(split[0], split[1], copy_alternative), copy_alternative)
    end

    c12 = copy_alternative.services_time - copy_original.services_time    
    c1 = (RoutesManager::VARIATIONS[constant][:alfa_1] * c11) + (RoutesManager::VARIATIONS[constant][:alfa_2] * c12)    
    cc = (RoutesManager::VARIATIONS[constant][:lambda] * $nodesManager.origin.calculate_time(node, copy_original.current_time)) - c1
    return cc

  end

  def to_s
    s = "[ "
    @route.each { |n| s += " #{ n.id + 1 } " }
    s += " ]"
  end

  def reset_attributes(object)
    object.arrival_time = Time.utc(2016,9,6,6,0)    
    object.wait_time = object.services_time = object.total_distance = object.total_service_time = 0
    object.demand = Gui.data[:capacity]
  end

  private
  def criterion_1
    max_node($nodesManager.origin)
  end

  def criterion_2
    min_time
  end

  def max_node(nodeB)        
    max_time = -999
    node = nil
    $nodesManager.nodes.each do |nodeA|
      time = -999  
      time = nodeB.calculate_time(nodeA, Time.utc(2016,9,6,6,0) ) if nodeA != nodeB
      if time > max_time
        max_time = time
        node = nodeA
      end
    end
    node
  end

  def min_time
    $nodesManager.unvisited.first
  end

  def add(node, position = -1)
    node_added = node == $nodesManager.origin ? $nodesManager.origin : $nodesManager.unvisited.delete(node)
    @route.insert(position, node_added)
  end

  def ready_time(node_j, arrival_time)
    if arrival_time < node_j.ready_time
      node_j.ready_time - arrival_time
    elsif arrival_time >= node_j.ready_time && arrival_time <= node_j.due_time
      0
    end
  end

  # Divide the route in pairs. I.e: [1,2,3,4,5] -> [1,2] [2,3] [3,4] [4,5]
  def split_routes(route = @route)
    (0..route.size - 2).map { |x| node_i, node_j = route[x, 2] }
  end

  # Receive a hash as parameter
  # services_time = tiempo de inicio de servicio
  def assign_values(values, object = self)
    object.arrival_time = values[:arrival_time]
    object.total_distance += values[:distance]
    object.wait_time += values[:wait_time]
    object.services_time = values[:services_time]
    object.total_service_time += values[:total_service_time]
  end

end

class RoutesManager

  attr_accessor :routes, :capacity, :vehicles

  VARIATIONS = {}
  VARIATIONS[1] =  { alfa_1: 1, alfa_2: 0, m: 1, lambda: 1 }
  VARIATIONS[2] =  { alfa_1: 1, alfa_2: 0, m: 1, lambda: 2 }
  VARIATIONS[3] =  { alfa_1: 0, alfa_2: 1, m: 1, lambda: 1 }
  VARIATIONS[4] =  { alfa_1: 0, alfa_2: 1, m: 1, lambda: 2 }

  def initialize(capacity, vehicles)
    @routes = {}
    @routes[:criterion_1] = {}
    @routes[:criterion_2] = {}
    @capacity, @vehicles = capacity, vehicles
    create_routes
  end

  def create_routes
    (1..4).each do |criterion|
      #@routes[:criterion_1][criterion] = []
      #@routes[:criterion_2][criterion] = []
      @routes[:criterion_1][criterion] = generate_routes(1, criterion)
      @routes[:criterion_2][criterion] = generate_routes(2, criterion)
      #@routes[:criterion_2][4] = generate_routes(2, 4)
    end
  end

  # NOTE: when the criterion change the unvisted array should be reload
  def generate_routes(seed, criterion)
    routes = []
    unvisited_copy = $nodesManager.unvisited.clone
    route_original = Route.new(seed, @capacity)

    begin
      unvisited = $nodesManager.unvisited.clone
      new_route = node_added = nil
      max_c2 = -999999999999999

      # Insert a node in each posible position and choose the best option
      unvisited.each do |node|
        (1..route_original.route.size - 1).each do |position|
          alternative_route = route_original.clone
          alternative_route.route = route_original.route.clone
          alternative_route.demand  = @capacity
          alternative_route.arrival_time = alternative_route.wait_time = alternative_route.services_time = alternative_route.total_distance = alternative_route.total_service_time = 0
          if alternative_route.insert_node(node, position)
            c2 = alternative_route.calculate_c2(node, position, route_original, criterion)
            if c2 >= max_c2
              max_c2, new_route =  c2, alternative_route.clone
              new_route.route = alternative_route.route.clone
              node_added = node
            end
          end

          $nodesManager.unvisited = unvisited.clone
        end
      end

      # Assign the best route in the route original, and eliminated the node of the array unvisited
      if new_route.nil?
        routes << route_original
        route_original = Route.new(seed, @capacity)
        if $nodesManager.unvisited.empty?
          routes << route_original
        end
      else
        route_original = new_route.clone
        route_original.route = new_route.route.clone
        $nodesManager.unvisited = unvisited.clone
        $nodesManager.unvisited.delete(node_added)        
        routes << route_original if $nodesManager.unvisited.empty?
      end
    end while !$nodesManager.unvisited.empty?

    # Reset variables in order of find a new route
    $nodesManager.unvisited = unvisited_copy    
    routes
  end

  def total_distance(criterion, variables)
    criterion = criterion == 1 ? :criterion_1 : :criterion_2
    sum = 0
    @routes[criterion][variables].each { |route| sum += route.total_distance }
    sum
  end
end

# ------------------------ GUI ---------------------  #

class Gui
  include ConsoleViewHelper

  attr_accessor :data

  def initialize
    @@data = nil
  end

  def self.data
    @@data
  end

  def menu
    Gem.win_platform? ? system('cls') : system('clear')
    puts banner('Solomon instances', indent: 1)
    selected = list_files
    if selected
      #puts Benchmark.measure { $nodesManager = NodesManager.new(selected); routes_manager = RoutesManager.new(200, 25) }
      @@data = FileToNodes.getNodes(selected)
      $nodesManager =  explain('Reading file ', ' done') { NodesManager.new(@@data[:nodes]) }
      @routes_manager = explain('Creating routes ', ' done') { RoutesManager.new(@@data[:capacity], @@data[:vehicles_number]) }
      #cls
      #$Gem.win_platform? ? system('cls') : system('clear')
      puts Gem.win_platform? ? system('cls') : system('clear')
      Gem.win_platform? ? system('cls') : system('clear')
      show_routes
    end
  end

  def list_files
    # Get the name of the files in folder in
    files = Dir.glob('In/*.csv')
    files_parsed = files.map { |x| x.gsub('In/', '') }
    puts olist(files_parsed.push('Exit'), indent: 1)
    file_selected = nil

    loop do
      file_selected  = ConsoleViewHelper.input('choose intance:', 1)
      file_selected = file_selected.to_i
      break if file_selected <= files_parsed.count && file_selected >= 1
    end

    file_selected == files_parsed.count ? nil : files[file_selected - 1]
  end

  def show_routes

    (1..2).each do |criterion|
      puts criterion == 1 ? banner('Criterion 1',  width: 100) : banner('Criterion 2', width: 100)
      key = criterion == 1 ? :criterion_1 : :criterion_2
      puts nl
      (1..4).each do |value|
        puts "α1 = #{RoutesManager::VARIATIONS[value][:alfa_1]}, α2 = #{RoutesManager::VARIATIONS[value][:alfa_2]}, μ = #{RoutesManager::VARIATIONS[value][:m]}, λ = #{RoutesManager::VARIATIONS[value][:lambda]}"
        puts "Total distance: #{@routes_manager.total_distance(criterion, value)}"
        puts nl
        list = @routes_manager.routes[key][value].map { |route| "#{idt}#{route.to_s} #{nl}" \
                                                                          "#{idt}Distance: #{route.total_distance} #{nl}" \
                                                                          "#{idt}Waiting time: #{route.wait_time} #{nl}" \
                                                                          "#{idt}Services time: #{route.total_service_time} #{nl}"\
                                                                          "#{idt}Arrival time: #{route.arrival_time} #{nl}"\
                                                                          "#{idt}Demand: #{@@data[:capacity] - route.demand} "}
        puts olist(list)
        puts nl
      end

    end

  end
end




# -------------------- Main program -------------------- #

key = 'AIzaSyBnfnAQuz2ulq3ET3OY8p5uB0wSpDjfMYY';

GoogleMapsService.configure do |config|
  config.key = key
end
gui = Gui.new
gui.menu