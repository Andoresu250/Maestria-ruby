require 'google_maps_service'
require 'certified'
require 'csv'
require 'console_view_helper'
require 'net/http'
require 'uri'
require 'openssl'
require 'json'
OpenSSL::SSL::VERIFY_PEER = OpenSSL::SSL::VERIFY_NONE
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
    while(true)

      origin = @place.gsub('#', ' ').gsub(' ', '+')
      destination = node.place.gsub('#', ' ').gsub(' ', '+')
      date = time.to_i

      uri = 'https://maps.googleapis.com/maps/api/directions/json?' +
            "origin=#{origin}" + '&' +
            "destination=#{destination}" + '&' +
            'mode=driving' + '&' +
            "departure_time=#{date}" + '&' +
            'traffic_model=pessimistic' + '&' +
            "key=#{$new_keys[$new_index]}"      

      json_object = JSON.parse(Net::HTTP.get URI(uri))            
      if json_object['status'] == 'OK'
        #return json_object['routes'][0]['legs'][0]['duration_in_traffic']['value'].to_f
        return json_object['routes'][0]['legs'][0]['duration']['value'].to_f
        #return json_object['routes'][0]['legs'][0]['distance']['value'].to_f
      else
        p json_object['status']
        p "query limit se esperan 15 segundos..."
        sleep(15)
      end
    end
  end

  def calculate_distance(node, time)        
    while(true)

      origin = @place.gsub('#', ' ').gsub(' ', '+')
      destination = node.place.gsub('#', ' ').gsub(' ', '+')
      date = time.to_i

      uri = 'https://maps.googleapis.com/maps/api/directions/json?' +
            "origin=#{origin}" + '&' +
            "destination=#{destination}" + '&' +
            'mode=driving' + '&' +
            "departure_time=#{date}" + '&' +
            'traffic_model=pessimistic' + '&' +
            "key=#{$new_keys[$new_index]}"      

      json_object = JSON.parse(Net::HTTP.get URI(uri))            
      if json_object['status'] == 'OK'
        #return json_object['routes'][0]['legs'][0]['duration_in_traffic']['value'].to_f
        #return json_object['routes'][0]['legs'][0]['duration']['value'].to_f
        return json_object['routes'][0]['legs'][0]['distance']['value'].to_f
      else
        p json_object['status']
        p "query limit se esperan 15 segundos..."
        sleep(15)
      end
    end
  end

  def calculate_time_traffic(node, time)        
    while(true)

      origin = @place.gsub('#', ' ').gsub(' ', '+')
      destination = node.place.gsub('#', ' ').gsub(' ', '+')
      date = time.to_i

      uri = 'https://maps.googleapis.com/maps/api/directions/json?' +
            "origin=#{origin}" + '&' +
            "destination=#{destination}" + '&' +
            'mode=driving' + '&' +
            "departure_time=#{date}" + '&' +
            'traffic_model=pessimistic' + '&' +
            "key=#{$new_keys[$new_index]}"      

      json_object = JSON.parse(Net::HTTP.get URI(uri))            
      if json_object['status'] == 'OK'
        return json_object['routes'][0]['legs'][0]['duration_in_traffic']['value'].to_f
        #return json_object['routes'][0]['legs'][0]['duration']['value'].to_f
        #return json_object['routes'][0]['legs'][0]['distance']['value'].to_f
      else
        p json_object['status']
        p "query limit se esperan 15 segundos..."
        sleep(15)
      end
    end
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

  attr_accessor :route, :arrival_time, :arrival_time_traffic, :wait_time, :wait_time_traffic, :services_time, :total_distance, :total_time, :total_time_traffic ,:demand, :total_service_time, :current_time

  def initialize criterion, capacity
    @current_time = Time.utc(2016,9,6,6,0)
    @route = []
    @arrival_time = Time.utc(2016,9,6,6,0)
    @wait_time = @services_time = @total_distance = @total_service_time = @total_time = @total_time_traffic = @wait_time_traffic = 0
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
    time = node_i.calculate_distance(node_j, object.current_time)
    values[:arrival_time]  = wik + node_i.service_time + distance
    wait_time = ready_time(node_j, values[:arrival_time])

    demand = object.demand - node_i.demand
    if wait_time && demand >= 0
      values[:distance] = distance
      values[:time] = time
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
    @route.each { |n| s += " #{ n.id } " }
    s += " ]"
  end

  def reset_attributes(object)
    object.arrival_time = Time.utc(2016,9,6,6,0)    
    object.wait_time = object.services_time = object.total_distance = object.total_service_time = object.total_time = object.total_time_traffic = 0
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
    $nodesManager.unvisited.each do |nodeA|
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
    object.total_time += values[:time]
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
      @routes[:criterion_1][1] = generate_routes(1, 1)
      @routes[:criterion_1][2] = []
      @routes[:criterion_2][1] = []
      @routes[:criterion_2][2] = []    
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
        if $nodesManager.unvisited.empty?          
          routes << route_original 
        end        
      end
    end while !$nodesManager.unvisited.empty?

    # Reset variables in order of find a new route
    $nodesManager.unvisited = unvisited_copy 
    
    routes.each do |route|      
      timeAB = 0
      time_trafficAB = 0
      distanceAB = 0
      route_wait_time = 0      
      route_wait_time_traffic = 0
      current_time = route.route[0].ready_time + route.route[0].service_time
      current_time_traffic = route.route[0].ready_time + route.route[0].service_time
      (0..route.route.length-2).each do |index|

        nodeA = route.route[index]
        nodeB = route.route[index + 1]        

        timeAB += nodeA.calculate_time(nodeB, current_time)
        time_trafficAB += nodeA.calculate_time_traffic(nodeB, current_time_traffic)

        distanceAB += nodeA.calculate_distance(nodeB, current_time)            

        wait_time = 0        
        wait_time = nodeB.ready_time - (current_time + timeAB + nodeA.service_time) if current_time + timeAB + nodeA.service_time < nodeB.ready_time          

        wait_time_traffic = 0        
        wait_time_traffic = nodeB.ready_time - (current_time_traffic + time_trafficAB + nodeA.service_time) if current_time_traffic + time_trafficAB + nodeA.service_time < nodeB.ready_time          

        current_time += (nodeA.service_time + wait_time + timeAB)
        current_time_traffic += (nodeA.service_time + wait_time_traffic + time_trafficAB)

        route_wait_time += wait_time
        route_wait_time_traffic += wait_time_traffic

        timeAB += nodeA.service_time + wait_time        
        time_trafficAB += nodeA.service_time + wait_time_traffic

      end
      route.total_distance = timeAB
      route.total_time = distanceAB
      route.total_time_traffic = time_trafficAB
      route.wait_time = route_wait_time
      route.wait_time_traffic = route_wait_time_traffic
      route.arrival_time = $nodesManager.origin.ready_time + timeAB
      route.arrival_time_traffic = $nodesManager.origin.ready_time + time_trafficAB
    end
  end

  def total_distance(criterion, variables)
    criterion = criterion == 1 ? :criterion_1 : :criterion_2
    sum = 0
    begin
      @routes[criterion][variables].each { |route| sum += route.total_distance }
    rescue

    end
    sum
  end

  def total_time(criterion, variables)
    criterion = criterion == 1 ? :criterion_1 : :criterion_2
    sum = 0
    begin
      @routes[criterion][variables].each { |route| sum += route.total_time }
    rescue

    end
    sum
  end

  def total_time_traffic(criterion, variables)
    criterion = criterion == 1 ? :criterion_1 : :criterion_2
    sum = 0
    begin
      @routes[criterion][variables].each { |route| sum += route.total_time_traffic }
    rescue

    end
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
    puts banner('Files', indent: 1)
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

    (1..1).each do |criterion|
      puts criterion == 1 ? banner('Criterion 1',  width: 100) : banner('Criterion 2', width: 100)
      key = criterion == 1 ? :criterion_1 : :criterion_2
      puts nl
      (1..1).each do |value|
        puts "α1 = #{RoutesManager::VARIATIONS[value][:alfa_1]}, α2 = #{RoutesManager::VARIATIONS[value][:alfa_2]}, μ = #{RoutesManager::VARIATIONS[value][:m]}, λ = #{RoutesManager::VARIATIONS[value][:lambda]}"
        puts "Total Time: #{@routes_manager.total_distance(criterion, value)}"
        puts "Total Time with traffic: #{@routes_manager.total_time_traffic(criterion, value)}"
        puts "Total Distance: #{@routes_manager.total_time(criterion, value)}"

        puts nl        
        list = @routes_manager.routes[key][value].map { |route| "#{idt}#{route.to_s} #{nl}" \
                                                                        "#{idt}Time: #{route.total_distance} s #{nl}" \
                                                                        "#{idt}Time with traffic: #{route.total_time_traffic} s #{nl}" \
                                                                        "#{idt}Distance: #{route.total_time} s #{nl}" \
                                                                        "#{idt}Waiting time: #{route.wait_time} s #{nl}" \
                                                                        "#{idt}Waiting time with traffic: #{route.wait_time_traffic} s #{nl}" \
                                                                        "#{idt}Services time: #{route.total_service_time} #{nl}"\
                                                                        "#{idt}Arrival time: #{route.arrival_time} #{nl}"\
                                                                        "#{idt}Arrival time with traffic: #{route.arrival_time_traffic} #{nl}"\
                                                                        "#{idt}Demand: #{@@data[:capacity] - route.demand} "}
        list_string = olist(list)
        out_file = File.new("out.txt", "w")    
        out_file.puts(list_string.to_s)
        out_file.close
        puts list_string
        puts nl
      end

    end
    final_path = []  
    points = [] 
    routes_size = []  
    @routes_manager.routes[:criterion_1][1].each do |route|
      route.route.each { |node| points.push(node.place) }      
      (0..route.route.size-2).each do |i|      
        final_path.push({from: route.route[i].place, to: route.route[i + 1].place})
      end    
      routes_size.push(route.route.size - 1)        
    end
    (1..routes_size.size-1).each do |index|
      routes_size[index] += routes_size[index-1]
    end
    points = points.uniq


    text = File.read("index_template.html")
    new_contents = text.gsub('**cities**', "#{final_path.to_json}")
    new_contents = new_contents.gsub('**nonclusters**', "#{points.to_json}")
    new_contents = new_contents.gsub('**routesSize**', "#{routes_size.to_json}")
    File.open("output.html", "w") {|file| file.puts new_contents }
    system("open output.html")
    return
  end
end




# -------------------- Main program -------------------- #

$keys = ['AIzaSyBnfnAQuz2ulq3ET3OY8p5uB0wSpDjfMYY', 'AIzaSyA8fgbD07roSeqUnCt25fk_g7wqP6O4nlU', 'AIzaSyAMXM81rmNJriowbyssNGgsD1zh1k8jyuY', 'AIzaSyA2Ch402MT8YquRQb7yY54EL1H25NcT3VU'];
$new_keys = ['AIzaSyCmtBZiwE3OKQB5MuE32GrIsiBYWKvCafY']
$index = 0
$new_index = 0
GoogleMapsService.configure do |config|
  config.key = $keys[$index]
end
gui = Gui.new
gui.menu