require_relative "../helpers/geometry"

module AresMUSH
  module Space
    describe Geometry do

      describe "square geometry" do
        let(:mode) { "square" }

        it "has eight facings" do
          expect(Geometry.facing_count(mode)).to eq 8
          expect(Geometry.facing_names(mode)).to eq %w(N NE E SE S SW W NW)
        end

        it "translates along each facing" do
          expect(Geometry.translate(mode, [5, 5], 0)).to eq [5, 4]   # N
          expect(Geometry.translate(mode, [5, 5], 2)).to eq [6, 5]   # E
          expect(Geometry.translate(mode, [5, 5], 4)).to eq [5, 6]   # S
          expect(Geometry.translate(mode, [5, 5], 6)).to eq [4, 5]   # W
          expect(Geometry.translate(mode, [5, 5], 1, 3)).to eq [8, 2] # NE x3
        end

        it "uses chebyshev distance so diagonals cost one" do
          expect(Geometry.distance(mode, [0, 0], [3, 0])).to eq 3
          expect(Geometry.distance(mode, [0, 0], [3, 3])).to eq 3
          expect(Geometry.distance(mode, [0, 0], [1, 4])).to eq 4
          expect(Geometry.distance(mode, [2, 2], [2, 2])).to eq 0
        end

        it "computes bearings in all eight directions" do
          origin = [5, 5]
          expect(Geometry.bearing(mode, origin, [5, 1])).to eq 0  # N
          expect(Geometry.bearing(mode, origin, [9, 1])).to eq 1  # NE
          expect(Geometry.bearing(mode, origin, [9, 5])).to eq 2  # E
          expect(Geometry.bearing(mode, origin, [9, 9])).to eq 3  # SE
          expect(Geometry.bearing(mode, origin, [5, 9])).to eq 4  # S
          expect(Geometry.bearing(mode, origin, [1, 9])).to eq 5  # SW
          expect(Geometry.bearing(mode, origin, [1, 5])).to eq 6  # W
          expect(Geometry.bearing(mode, origin, [1, 1])).to eq 7  # NW
        end

        it "has no bearing to itself" do
          expect(Geometry.bearing(mode, [3, 3], [3, 3])).to be_nil
          expect(Geometry.arc(mode, [3, 3], 0, [3, 3])).to be_nil
        end

        it "parses facing names and indices, rejecting nonsense" do
          expect(Geometry.parse_facing(mode, "ne")).to eq 1
          expect(Geometry.parse_facing(mode, "S")).to eq 4
          expect(Geometry.parse_facing(mode, "7")).to eq 7
          expect(Geometry.parse_facing(mode, "8")).to be_nil
          expect(Geometry.parse_facing(mode, "up")).to be_nil
          expect(Geometry.parse_facing(mode, nil)).to be_nil
        end

        it "turns by the shortest path" do
          expect(Geometry.turn_cost(mode, 0, 1)).to eq 1
          expect(Geometry.turn_cost(mode, 0, 7)).to eq 1
          expect(Geometry.turn_cost(mode, 0, 4)).to eq 4
          expect(Geometry.turn_cost(mode, 6, 2)).to eq 4
          expect(Geometry.turn_cost(mode, 3, 3)).to eq 0
        end

        describe "arcs with the forward diagonal bias" do
          it "puts the bow diagonals in the forward arc" do
            # Ship at 5,5 facing N.
            expect(Geometry.arc(mode, [5, 5], 0, [5, 1])).to eq :forward   # dead ahead
            expect(Geometry.arc(mode, [5, 5], 0, [9, 1])).to eq :forward   # bow starboard
            expect(Geometry.arc(mode, [5, 5], 0, [1, 1])).to eq :forward   # bow port
            expect(Geometry.arc(mode, [5, 5], 0, [9, 5])).to eq :starboard
            expect(Geometry.arc(mode, [5, 5], 0, [1, 5])).to eq :port
            expect(Geometry.arc(mode, [5, 5], 0, [5, 9])).to eq :aft
            expect(Geometry.arc(mode, [5, 5], 0, [9, 9])).to eq :aft
          end

          it "rotates the arcs with the ship" do
            # Same target, ship now facing E: what was ahead is now to port.
            expect(Geometry.arc(mode, [5, 5], 2, [5, 1])).to eq :port
            expect(Geometry.arc(mode, [5, 5], 2, [9, 5])).to eq :forward
            expect(Geometry.arc(mode, [5, 5], 2, [1, 5])).to eq :aft
            expect(Geometry.arc(mode, [5, 5], 2, [5, 9])).to eq :starboard
          end
        end

        describe "arcs with the broadside diagonal bias" do
          it "narrows the bow and widens the beams" do
            expect(Geometry.arc(mode, [5, 5], 0, [5, 1], "broadside")).to eq :forward
            expect(Geometry.arc(mode, [5, 5], 0, [9, 1], "broadside")).to eq :starboard
            expect(Geometry.arc(mode, [5, 5], 0, [1, 1], "broadside")).to eq :port
            expect(Geometry.arc(mode, [5, 5], 0, [5, 9], "broadside")).to eq :aft
          end
        end
      end

      describe "hex geometry" do
        let(:mode) { "hex" }

        it "has six facings" do
          expect(Geometry.facing_count(mode)).to eq 6
          expect(Geometry.facing_names(mode)).to eq %w(NE E SE SW W NW)
        end

        it "translates along each facing" do
          expect(Geometry.translate(mode, [0, 0], 0)).to eq [1, -1]  # NE
          expect(Geometry.translate(mode, [0, 0], 1)).to eq [1, 0]   # E
          expect(Geometry.translate(mode, [0, 0], 2)).to eq [0, 1]   # SE
          expect(Geometry.translate(mode, [0, 0], 3)).to eq [-1, 1]  # SW
          expect(Geometry.translate(mode, [0, 0], 4)).to eq [-1, 0]  # W
          expect(Geometry.translate(mode, [0, 0], 5)).to eq [0, -1]  # NW
        end

        it "uses axial hex distance" do
          expect(Geometry.distance(mode, [0, 0], [1, 0])).to eq 1
          expect(Geometry.distance(mode, [0, 0], [0, -1])).to eq 1
          expect(Geometry.distance(mode, [0, 0], [1, -1])).to eq 1
          expect(Geometry.distance(mode, [0, 0], [3, 0])).to eq 3
          expect(Geometry.distance(mode, [0, 0], [-2, 1])).to eq 2
        end

        it "reports each neighbour's bearing as its own direction" do
          6.times do |facing|
            neighbour = Geometry.translate(mode, [0, 0], facing)
            expect(Geometry.bearing(mode, [0, 0], neighbour)).to eq facing
          end
        end

        it "keeps bearings stable at longer range" do
          6.times do |facing|
            far = Geometry.translate(mode, [0, 0], facing, 4)
            expect(Geometry.bearing(mode, [0, 0], far)).to eq facing
          end
        end

        it "splits six facings evenly into four arcs" do
          # Facing NE (0).
          expect(Geometry.arc(mode, [0, 0], 0, [1, -1])).to eq :forward
          expect(Geometry.arc(mode, [0, 0], 0, [1, 0])).to eq :starboard
          expect(Geometry.arc(mode, [0, 0], 0, [0, 1])).to eq :starboard
          expect(Geometry.arc(mode, [0, 0], 0, [-1, 1])).to eq :aft
          expect(Geometry.arc(mode, [0, 0], 0, [-1, 0])).to eq :port
          expect(Geometry.arc(mode, [0, 0], 0, [0, -1])).to eq :port
        end

        it "turns by the shortest path around six facings" do
          expect(Geometry.turn_cost(mode, 0, 5)).to eq 1
          expect(Geometry.turn_cost(mode, 0, 3)).to eq 3
          expect(Geometry.turn_cost(mode, 4, 1)).to eq 3
        end
      end

      describe "arc coverage" do
        it "assigns every relative bearing to exactly one arc in both geometries" do
          %w(square hex).each do |mode|
            count = Geometry.facing_count(mode)
            %w(forward broadside).each do |bias|
              arcs = (0...count).map { |b| Geometry.arc_for_bearing(mode, 0, b, bias) }
              expect(arcs.compact.count).to eq count
              expect(arcs.uniq.sort_by(&:to_s)).to eq [ :aft, :forward, :port, :starboard ]
            end
          end
        end
      end
    end
  end
end
