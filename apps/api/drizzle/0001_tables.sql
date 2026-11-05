CREATE TABLE "city" (
	"id" text PRIMARY KEY NOT NULL,
	"name_ka" text NOT NULL,
	"name_en" text NOT NULL,
	"osm_relation_id" bigint NOT NULL,
	"area_m2" double precision NOT NULL,
	"boundary" geometry(MultiPolygon, 4326) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "district" (
	"id" text PRIMARY KEY NOT NULL,
	"city_id" text NOT NULL,
	"kind" text NOT NULL,
	"osm_relation_id" bigint,
	"name_ka" text NOT NULL,
	"name_en" text,
	"area_m2" double precision NOT NULL,
	"boundary" geometry(MultiPolygon, 4326) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "pack" (
	"city_id" text NOT NULL,
	"version" text NOT NULL,
	"file" text NOT NULL,
	"sha256" text NOT NULL,
	"size" bigint NOT NULL,
	"osm_timestamp" timestamp with time zone NOT NULL,
	"published_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pack_city_id_version_pk" PRIMARY KEY("city_id","version")
);
--> statement-breakpoint
CREATE TABLE "street" (
	"id" uuid PRIMARY KEY NOT NULL,
	"city_id" text NOT NULL,
	"name_ka" text NOT NULL,
	"name_en" text,
	"road_class" text NOT NULL,
	"difficulty" text NOT NULL,
	"length_m" double precision NOT NULL,
	"geom" geometry(MultiLineString, 4326) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "street_district" (
	"street_id" uuid NOT NULL,
	"district_id" text NOT NULL,
	"length_m" double precision NOT NULL,
	"share" double precision NOT NULL,
	CONSTRAINT "street_district_street_id_district_id_pk" PRIMARY KEY("street_id","district_id")
);
--> statement-breakpoint
ALTER TABLE "district" ADD CONSTRAINT "district_city_id_city_id_fk" FOREIGN KEY ("city_id") REFERENCES "public"."city"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pack" ADD CONSTRAINT "pack_city_id_city_id_fk" FOREIGN KEY ("city_id") REFERENCES "public"."city"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "street" ADD CONSTRAINT "street_city_id_city_id_fk" FOREIGN KEY ("city_id") REFERENCES "public"."city"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "street_district" ADD CONSTRAINT "street_district_street_id_street_id_fk" FOREIGN KEY ("street_id") REFERENCES "public"."street"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "street_district" ADD CONSTRAINT "street_district_district_id_district_id_fk" FOREIGN KEY ("district_id") REFERENCES "public"."district"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "district_boundary_index" ON "district" USING gist ("boundary");--> statement-breakpoint
CREATE INDEX "street_geom_index" ON "street" USING gist ("geom");