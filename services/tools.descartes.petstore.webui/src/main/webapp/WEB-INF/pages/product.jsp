<%@include file="head.jsp"%>


<%@include file="header.jsp"%>

<div class="container" id="main">


	<div class="row">

		<%@include file="categorylist.jsp"%>

		<div class="col-sm-6">

			<h2 class="category-title">${product.name}</h2>

			<form action="cartAction" method="POST">
				<div class="row">
					<input type='hidden' name="productid" value="${product.id}">
					<div class="col-sm-12">
						<img class="productpicture"
							src="${productImage}"
							alt="${product.name}">
					</div>
					<div class="col-sm-12 ">
						<blockquote>${product.description}</blockquote>

						<span> Price: <fmt:formatNumber
								value="${product.listPriceInCents/100}" type="currency"
								currencySymbol="$" />
						</span>
					</div>
				</div>
				<input name="addToCart" class="btn" value="Add to Cart" type="submit">
			</form>



		</div>

		<%@include file="recommender.jsp"%>


	</div>


</div>

</div>


<%@include file="footer.jsp"%>

