

"""
find_best_assignment(C, maximize=false) = solution

Solve the two-dimensional assignment problem with a rectangular cost matrix C, 
scanning row-wise.

# Example 
```julia
julia> M=rand(1:100,3,4)
3×4 Matrix{Int64}:
 55  17  88  52
 29  38  90  20
 63  23  19  87

julia> sol = find_best_assignment(M)
AssignmentSolution(CartesianIndex.(1:3, [2, 4, 3]), 56)

julia> sum(M[sol])
56

julia> max_sol = find_best_assignment(M, true)
AssignmentSolution(CartesianIndex.(1:3, [1, 3, 4]), 232)
```

This code is a port of Matlab code released [1] in the public domain by the
US Naval Research Laboratory. 

This work is not affliated or endorsed by the Naval Research Laboratory.

The algorithm is described in detail in 
D. F. Crouse, "Advances in displaying uncertain estimates of multiple
targets," in Proceedings of SPIE: Signal Processing, Sensor Fusion, and
Target Recognition XXII, vol. 8745, Baltimore, MD, Apr. 2013.

REFERENCES:
[1] D. F. Crouse, "The Tracker Component Library: Free Routines for Rapid 
   Prototyping," IEEE Aerospace and Electronic Systems Magazine, vol. 32, 
   no. 5, pp. 18-27, May. 2017
"""
function find_best_assignment(C::AbstractMatrix{T}, maximize::Bool=false) where T
	   
    numRow, numCol = size(C)
	gain = nothing
    
    numCol > numRow && return find_best_assignment(C', maximize)'
	
	# The cost matrix must have all non-negative elements for the assignment
	# algorithm to work. This forces all of the elements to be positive. The
	# delta is added back in when computing the gain in the end.
    if maximize
        CDelta=maximum(C)
        C =-C .+ CDelta
    else
        CDelta=minimum(C)
        C = C .- CDelta
    end

    # These store the assignment as it is made.
    col4row=zeros(Int, numRow)
    row4col=zeros(Int, numCol)
    u=zeros(T, numCol) # The dual variable for the columns
    v=zeros(T, numRow) # The dual variable for the rows.
	
	pred = zeros(Int, numRow)
	ScannedCols = falses(numCol)
	ScannedRow = falses(numRow)
	Row2Scan = zeros(Int, numRow)
	# Need to be able to fill with infinity
	shortestPathCost = fill(typemax(float(T)), numRow)
	
	# Initially, none of the columns are assigned.
    for curUnassCol = 1:numCol       
        # This finds the shortest augmenting path starting at k and returns
        # the last node in the path.
        sink, pred, u, v = ShortestPath!(
			curUnassCol,u,v,C,col4row,row4col,
			pred,ScannedCols,ScannedRow,Row2Scan,shortestPathCost
		)
        
        # If the problem is infeasible, mark it as such and return.
		sink == 0 && return AssignmentSolution(row4col, col4row, gain, v, u)
        
        # We have to remove node k from those that must be assigned.
        j = sink
        while true
            i = col4row[j] = pred[j]
            j, row4col[i] = row4col[i], j   			
			
            if i == curUnassCol 
				break
			end
        end
    end
	

	gain = maximize ? - CDelta*numCol : CDelta*numCol
	for curCol=1:numCol
		gain += C[row4col[curCol],curCol]
	end

	return AssignmentSolution(col4row, row4col, maximize ? -gain : gain, u, v)
end


function ShortestPath!(
		curUnassCol::Int,
		u::AbstractVector{T},
		v::AbstractVector{T},
		C::AbstractMatrix{T},
		col4row::AbstractVector{<:Integer},
		row4col::AbstractVector{<:Integer}, 
		pred::AbstractVector{<:Integer} = zeros(Int, size(C, 1)), 
		ScannedCols::AbstractVector{<:Bool} = falses(size(C,2)), 
		ScannedRow::AbstractVector{<:Bool} = falses(size(C,2)), 
		Row2Scan::AbstractVector{<:Integer} = Vector(1:size(C, 1)),
    	shortestPathCost::AbstractVector = fill(Inf, size(C, 1))
	) where T
    # This assumes that unassigned columns go from 1:numUnassigned
    numRow, numCol = size(C)
	
	pred .= 0
    # Initially, none of the rows and columns have been scanned.
    # This will store a 1 in every column that has been scanned.
	ScannedCols .= false 
    # This will store a 1 in every row that has been scanned.
	ScannedRow .= false
	Row2Scan .= 1:numRow # Columns left to scan.
    numRow2Scan = numRow
    
    sink=0
    delta=T(0)
	closestRowScan = -1
    curCol=curUnassCol
    shortestPathCost .= Inf
    
    while sink==0        
        # Mark the current row as having been visited.
        ScannedCols[curCol] = 1
        
        # Scan all of the columns that have not already been scanned.
        minVal = Inf
        @inbounds for curRowScan=1:numRow2Scan
            curRow=Row2Scan[curRowScan]
            reducedCost = delta + C[curRow,curCol] - u[curCol] - v[curRow];
            if reducedCost < shortestPathCost[curRow]
                pred[curRow] = curCol;
                shortestPathCost[curRow]=reducedCost;
            end
            
            #Find the minimum unassigned column that was
            #scanned.
            if shortestPathCost[curRow]<minVal 
                minVal=shortestPathCost[curRow];
                closestRowScan=curRowScan;
            end
        end
                
	   #If the minimum cost column is not finite, then the problem is
	   #not feasible.
        isfinite(minVal) || return 0, pred, u, v
        
        closestRow = Row2Scan[closestRowScan]
        #Add the column to the list of scanned columns and delete it from
        #the list of columns to scan.
        ScannedRow[closestRow] = 1;
        numRow2Scan -= 1;
		@inbounds for i in closestRowScan:numRow2Scan
			Row2Scan[i] = Row2Scan[i + 1]
		end
        
        delta=shortestPathCost[closestRow];
        #If we have reached an unassigned row.
        if col4row[closestRow]==0
            sink=closestRow;
        else
            curCol=col4row[closestRow];
        end
    end
    
    #Dual Update Step
    
    #Update the first row in the augmenting path.
    u[curUnassCol] += delta
	
    #Update the rest of the rows in the agumenting path.
	@inbounds for (i, col) in enumerate(ScannedCols)
		if col != 0 && i != curUnassCol
			u[i] += delta - shortestPathCost[row4col[i]]
		end
	end
    
    # Update the scanned columns in the augmenting path.
	@inbounds for (i, row) in enumerate(ScannedRow)
		if row != 0
			v[i] -= delta - shortestPathCost[i]
		end
	end
	
	return sink, pred, u, v
end